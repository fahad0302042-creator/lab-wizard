-- Lab Wizard Multi-Lab & Multi-Organization Migration (ORG-01)
-- ADDITIVE ONLY: adds organizations, labs, organization_members, and lab_members
-- tables, along with optional nullable organization_id and lab_id columns on
-- chemicals, apparatus, and consumption_logs. Existing single-user rows remain
-- personal (organization_id and lab_id are null) and accessible via the existing
-- user_id = auth.uid() RLS policies. The Next.js web app remains 100% compatible.
-- Safe to run repeatedly.

-- =============================================================================
-- 1. TABLES
-- =============================================================================

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  constraint org_user_unique unique (organization_id, user_id)
);

create table if not exists public.labs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  lab_type text not null default 'general',
  room_number text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.lab_members (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('manager', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  constraint lab_user_unique unique (lab_id, user_id)
);

-- =============================================================================
-- 2. ADDITIVE COLUMNS ON INVENTORY TABLES
-- =============================================================================

alter table public.chemicals
  add column if not exists organization_id uuid references public.organizations(id) on delete set null,
  add column if not exists lab_id uuid references public.labs(id) on delete set null;

alter table public.apparatus
  add column if not exists organization_id uuid references public.organizations(id) on delete set null,
  add column if not exists lab_id uuid references public.labs(id) on delete set null;

alter table public.consumption_logs
  add column if not exists organization_id uuid references public.organizations(id) on delete set null,
  add column if not exists lab_id uuid references public.labs(id) on delete set null;

-- Indexes for efficient lab-scoped queries
create index if not exists idx_chemicals_lab
  on public.chemicals(lab_id)
  where lab_id is not null;

create index if not exists idx_apparatus_lab
  on public.apparatus(lab_id)
  where lab_id is not null;

create index if not exists idx_consumption_logs_lab
  on public.consumption_logs(lab_id)
  where lab_id is not null;

-- =============================================================================
-- 3. ROW LEVEL SECURITY POLICIES
-- =============================================================================

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.labs enable row level security;
alter table public.lab_members enable row level security;

-- Organizations RLS
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'organizations' and policyname = 'organizations_select_member') then
    create policy "organizations_select_member" on public.organizations
      for select using (
        created_by = auth.uid() or
        exists (select 1 from public.organization_members where organization_id = organizations.id and user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'organizations' and policyname = 'organizations_insert_auth') then
    create policy "organizations_insert_auth" on public.organizations
      for insert with check (auth.uid() = created_by);
  end if;

  if not exists (select 1 from pg_policies where tablename = 'organizations' and policyname = 'organizations_update_admin') then
    create policy "organizations_update_admin" on public.organizations
      for update using (
        created_by = auth.uid() or
        exists (select 1 from public.organization_members where organization_id = organizations.id and user_id = auth.uid() and role in ('owner', 'admin'))
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'organizations' and policyname = 'organizations_delete_owner') then
    create policy "organizations_delete_owner" on public.organizations
      for delete using (
        created_by = auth.uid() or
        exists (select 1 from public.organization_members where organization_id = organizations.id and user_id = auth.uid() and role = 'owner')
      );
  end if;
end
$$;

-- Organization Members RLS
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'organization_members' and policyname = 'org_members_select') then
    create policy "org_members_select" on public.organization_members
      for select using (
        user_id = auth.uid() or
        exists (select 1 from public.organization_members m where m.organization_id = organization_members.organization_id and m.user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'organization_members' and policyname = 'org_members_insert_admin') then
    create policy "org_members_insert_admin" on public.organization_members
      for insert with check (
        exists (select 1 from public.organizations o where o.id = organization_members.organization_id and o.created_by = auth.uid()) or
        exists (select 1 from public.organization_members m where m.organization_id = organization_members.organization_id and m.user_id = auth.uid() and m.role in ('owner', 'admin'))
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'organization_members' and policyname = 'org_members_delete_admin') then
    create policy "org_members_delete_admin" on public.organization_members
      for delete using (
        user_id = auth.uid() or
        exists (select 1 from public.organization_members m where m.organization_id = organization_members.organization_id and m.user_id = auth.uid() and m.role in ('owner', 'admin'))
      );
  end if;
end
$$;

-- Labs RLS
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'labs' and policyname = 'labs_select_member') then
    create policy "labs_select_member" on public.labs
      for select using (
        exists (select 1 from public.organization_members where organization_id = labs.organization_id and user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'labs' and policyname = 'labs_insert_admin') then
    create policy "labs_insert_admin" on public.labs
      for insert with check (
        exists (select 1 from public.organization_members where organization_id = labs.organization_id and user_id = auth.uid() and role in ('owner', 'admin'))
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'labs' and policyname = 'labs_update_admin') then
    create policy "labs_update_admin" on public.labs
      for update using (
        exists (select 1 from public.organization_members where organization_id = labs.organization_id and user_id = auth.uid() and role in ('owner', 'admin')) or
        exists (select 1 from public.lab_members where lab_id = labs.id and user_id = auth.uid() and role = 'manager')
      );
  end if;
end
$$;

-- Lab Members RLS
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'lab_members' and policyname = 'lab_members_select') then
    create policy "lab_members_select" on public.lab_members
      for select using (
        exists (select 1 from public.labs l join public.organization_members om on om.organization_id = l.organization_id where l.id = lab_members.lab_id and om.user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'lab_members' and policyname = 'lab_members_manage') then
    create policy "lab_members_manage" on public.lab_members
      for all using (
        exists (select 1 from public.labs l join public.organization_members om on om.organization_id = l.organization_id where l.id = lab_members.lab_id and om.user_id = auth.uid() and om.role in ('owner', 'admin')) or
        exists (select 1 from public.lab_members lm where lm.lab_id = lab_members.lab_id and lm.user_id = auth.uid() and lm.role = 'manager')
      );
  end if;
end
$$;

-- Lab-scoped access to chemicals, apparatus, and logs (permissive OR with existing personal policy)
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'chemicals' and policyname = 'chemicals_select_lab') then
    create policy "chemicals_select_lab" on public.chemicals
      for select using (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = chemicals.lab_id and user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'chemicals' and policyname = 'chemicals_insert_lab') then
    create policy "chemicals_insert_lab" on public.chemicals
      for insert with check (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = chemicals.lab_id and user_id = auth.uid() and role in ('manager', 'member'))
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'chemicals' and policyname = 'chemicals_update_lab') then
    create policy "chemicals_update_lab" on public.chemicals
      for update using (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = chemicals.lab_id and user_id = auth.uid() and role in ('manager', 'member'))
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'apparatus' and policyname = 'apparatus_select_lab') then
    create policy "apparatus_select_lab" on public.apparatus
      for select using (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = apparatus.lab_id and user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'apparatus' and policyname = 'apparatus_insert_lab') then
    create policy "apparatus_insert_lab" on public.apparatus
      for insert with check (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = apparatus.lab_id and user_id = auth.uid() and role in ('manager', 'member'))
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'consumption_logs' and policyname = 'consumption_logs_select_lab') then
    create policy "consumption_logs_select_lab" on public.consumption_logs
      for select using (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = consumption_logs.lab_id and user_id = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where tablename = 'consumption_logs' and policyname = 'consumption_logs_insert_lab') then
    create policy "consumption_logs_insert_lab" on public.consumption_logs
      for insert with check (
        lab_id is not null and
        exists (select 1 from public.lab_members where lab_id = consumption_logs.lab_id and user_id = auth.uid() and role in ('manager', 'member'))
      );
  end if;
end
$$;

-- =============================================================================
-- 4. ATOMIC SETUP RPC FUNCTION
-- =============================================================================

create or replace function public.create_organization_with_lab(
  p_name text,
  p_slug text,
  p_default_lab_name text default 'Main Lab',
  p_lab_type text default 'general'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_org_id uuid;
  v_lab_id uuid;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- 1. Create organization
  insert into public.organizations (name, slug, created_by)
  values (p_name, lower(trim(p_slug)), v_uid)
  returning id into v_org_id;

  -- 2. Add creator as Owner
  insert into public.organization_members (organization_id, user_id, role)
  values (v_org_id, v_uid, 'owner');

  -- 3. Create default lab
  insert into public.labs (organization_id, name, lab_type)
  values (v_org_id, p_default_lab_name, p_lab_type)
  returning id into v_lab_id;

  -- 4. Add creator as Manager in the default lab
  insert into public.lab_members (lab_id, user_id, role)
  values (v_lab_id, v_uid, 'manager');

  return v_org_id;
end;
$$;

grant execute on function public.create_organization_with_lab(text, text, text, text) to authenticated;

comment on table public.organizations is 'Organizations for multi-lab collaboration (ORG-01).';
comment on table public.labs is 'Individual laboratory spaces within an organization (ORG-01).';

-- Ask PostgREST to reload schema
notify pgrst, 'reload schema';
