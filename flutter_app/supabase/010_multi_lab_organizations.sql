-- Lab Wizard Multi-Lab & Multi-Organization Migration (ORG-01)
-- ADDITIVE ONLY: adds organizations, labs, organization_members, and lab_members
-- tables, along with optional nullable organization_id and lab_id columns on
-- chemicals, apparatus, and consumption_logs. Existing single-user rows remain
-- personal (organization_id and lab_id are null) and accessible via the existing
-- user_id = auth.uid() RLS policies. The Next.js web app remains 100% compatible.
-- Safe to run repeatedly, including over an earlier copy of this script:
-- membership policies are dropped and recreated so they do not query their
-- own tables (PostgreSQL rejects that as infinite recursion).

-- =============================================================================
-- 1. TABLES
-- =============================================================================

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
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


-- =============================================================================
-- 5. REPAIR POLICIES, STOCK ACTIONS, AND OWNERSHIP
-- Re-running this file drops the policies from section 3 and recreates them.
-- Helpers are SECURITY DEFINER so a policy never queries its own table
-- (PostgreSQL rejects that as infinite recursion).
-- =============================================================================

create or replace function public.is_org_member(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.organization_members
    where organization_id = p_org and user_id = auth.uid()
  );
$$;

create or replace function public.is_org_admin(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    exists (
      select 1 from public.organizations
      where id = p_org and created_by = auth.uid()
    )
    or exists (
      select 1 from public.organization_members
      where organization_id = p_org
        and user_id = auth.uid()
        and role in ('owner', 'admin')
    )
  );
$$;

create or replace function public.is_org_owner(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    exists (
      select 1 from public.organizations
      where id = p_org and created_by = auth.uid()
    )
    or exists (
      select 1 from public.organization_members
      where organization_id = p_org
        and user_id = auth.uid()
        and role = 'owner'
    )
  );
$$;

create or replace function public.is_lab_member(p_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.lab_members
    where lab_id = p_lab and user_id = auth.uid()
  );
$$;

create or replace function public.lab_can_write(p_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.lab_members
    where lab_id = p_lab
      and user_id = auth.uid()
      and role in ('manager', 'member')
  );
$$;

create or replace function public.is_lab_manager(p_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.lab_members
    where lab_id = p_lab and user_id = auth.uid() and role = 'manager'
  );
$$;

create or replace function public.can_see_lab(p_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_lab_member(p_lab) or exists (
    select 1 from public.labs l
    where l.id = p_lab and public.is_org_member(l.organization_id)
  );
$$;

create or replace function public.can_manage_lab_members(p_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_lab_manager(p_lab) or exists (
    select 1 from public.labs l
    where l.id = p_lab and public.is_org_admin(l.organization_id)
  );
$$;

create or replace function public.can_mutate_inventory_item(
  p_user_id uuid,
  p_owner_id uuid,
  p_lab_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null and (
    p_owner_id = p_user_id
    or (p_lab_id is not null and public.lab_can_write(p_lab_id))
  );
$$;

revoke all on function public.is_org_member(uuid) from public, anon;
revoke all on function public.is_org_admin(uuid) from public, anon;
revoke all on function public.is_org_owner(uuid) from public, anon;
revoke all on function public.is_lab_member(uuid) from public, anon;
revoke all on function public.lab_can_write(uuid) from public, anon;
revoke all on function public.is_lab_manager(uuid) from public, anon;
revoke all on function public.can_see_lab(uuid) from public, anon;
revoke all on function public.can_manage_lab_members(uuid) from public, anon;
revoke all on function public.can_mutate_inventory_item(uuid, uuid, uuid) from public, anon;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.is_org_admin(uuid) to authenticated;
grant execute on function public.is_org_owner(uuid) to authenticated;
grant execute on function public.is_lab_member(uuid) to authenticated;
grant execute on function public.lab_can_write(uuid) to authenticated;
grant execute on function public.is_lab_manager(uuid) to authenticated;
grant execute on function public.can_see_lab(uuid) to authenticated;
grant execute on function public.can_manage_lab_members(uuid) to authenticated;
grant execute on function public.can_mutate_inventory_item(uuid, uuid, uuid) to authenticated;

-- Existing installs created this foreign key as ON DELETE CASCADE. Restrict
-- so a missed transfer cannot delete the organization with the user.
do $$
declare
  v_name text;
begin
  select c.conname into v_name
  from pg_constraint c
  join pg_attribute a
    on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
  where c.conrelid = 'public.organizations'::regclass
    and c.contype = 'f'
    and a.attname = 'created_by';
  if v_name is not null then
    execute format('alter table public.organizations drop constraint %I', v_name);
  end if;
  alter table public.organizations
    add constraint organizations_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete restrict;
end
$$;

drop policy if exists "organizations_select_member" on public.organizations;
drop policy if exists "organizations_insert_auth" on public.organizations;
drop policy if exists "organizations_update_admin" on public.organizations;
drop policy if exists "organizations_delete_owner" on public.organizations;
drop policy if exists "org_members_select" on public.organization_members;
drop policy if exists "org_members_insert_admin" on public.organization_members;
drop policy if exists "org_members_update_admin" on public.organization_members;
drop policy if exists "org_members_delete_admin" on public.organization_members;
drop policy if exists "labs_select_member" on public.labs;
drop policy if exists "labs_insert_admin" on public.labs;
drop policy if exists "labs_update_admin" on public.labs;
drop policy if exists "labs_delete_admin" on public.labs;
drop policy if exists "lab_members_select" on public.lab_members;
drop policy if exists "lab_members_manage" on public.lab_members;
drop policy if exists "chemicals_select_lab" on public.chemicals;
drop policy if exists "chemicals_insert_lab" on public.chemicals;
drop policy if exists "chemicals_update_lab" on public.chemicals;
drop policy if exists "chemicals_delete_lab" on public.chemicals;
drop policy if exists "apparatus_select_lab" on public.apparatus;
drop policy if exists "apparatus_insert_lab" on public.apparatus;
drop policy if exists "apparatus_update_lab" on public.apparatus;
drop policy if exists "apparatus_delete_lab" on public.apparatus;
drop policy if exists "consumption_logs_select_lab" on public.consumption_logs;
drop policy if exists "consumption_logs_insert_lab" on public.consumption_logs;

create policy "organizations_select_member" on public.organizations
  for select using (created_by = auth.uid() or public.is_org_member(id));
create policy "organizations_insert_auth" on public.organizations
  for insert with check (auth.uid() = created_by);
create policy "organizations_update_admin" on public.organizations
  for update using (public.is_org_admin(id))
  with check (public.is_org_admin(id));
create policy "organizations_delete_owner" on public.organizations
  for delete using (public.is_org_owner(id));

create policy "org_members_select" on public.organization_members
  for select using (user_id = auth.uid() or public.is_org_member(organization_id));
create policy "org_members_insert_admin" on public.organization_members
  for insert with check (public.is_org_admin(organization_id));
create policy "org_members_update_admin" on public.organization_members
  for update using (public.is_org_admin(organization_id))
  with check (public.is_org_admin(organization_id));
create policy "org_members_delete_admin" on public.organization_members
  for delete using (user_id = auth.uid() or public.is_org_admin(organization_id));

create policy "labs_select_member" on public.labs
  for select using (public.is_org_member(organization_id));
create policy "labs_insert_admin" on public.labs
  for insert with check (public.is_org_admin(organization_id));
create policy "labs_update_admin" on public.labs
  for update using (public.is_org_admin(organization_id) or public.is_lab_manager(id))
  with check (public.is_org_admin(organization_id) or public.is_lab_manager(id));
create policy "labs_delete_admin" on public.labs
  for delete using (public.is_org_admin(organization_id));

create policy "lab_members_select" on public.lab_members
  for select using (public.can_see_lab(lab_id));
create policy "lab_members_manage" on public.lab_members
  for all
  using (public.can_manage_lab_members(lab_id))
  with check (public.can_manage_lab_members(lab_id));

create policy "chemicals_select_lab" on public.chemicals
  for select using (lab_id is not null and public.is_lab_member(lab_id));
create policy "chemicals_insert_lab" on public.chemicals
  for insert with check (lab_id is not null and public.lab_can_write(lab_id));
create policy "chemicals_update_lab" on public.chemicals
  for update
  using (lab_id is not null and public.lab_can_write(lab_id))
  with check (lab_id is not null and public.lab_can_write(lab_id));
create policy "chemicals_delete_lab" on public.chemicals
  for delete using (lab_id is not null and public.lab_can_write(lab_id));

create policy "apparatus_select_lab" on public.apparatus
  for select using (lab_id is not null and public.is_lab_member(lab_id));
create policy "apparatus_insert_lab" on public.apparatus
  for insert with check (lab_id is not null and public.lab_can_write(lab_id));
create policy "apparatus_update_lab" on public.apparatus
  for update
  using (lab_id is not null and public.lab_can_write(lab_id))
  with check (lab_id is not null and public.lab_can_write(lab_id));
create policy "apparatus_delete_lab" on public.apparatus
  for delete using (lab_id is not null and public.lab_can_write(lab_id));

create policy "consumption_logs_select_lab" on public.consumption_logs
  for select using (lab_id is not null and public.is_lab_member(lab_id));
create policy "consumption_logs_insert_lab" on public.consumption_logs
  for insert with check (lab_id is not null and public.lab_can_write(lab_id));

-- A personal update policy can still change lab_id, because it only checks
-- user_id. Stop a shared row being pulled into a personal notebook.
create or replace function public.protect_shared_lab_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and old.lab_id is not null
     and new.lab_id is distinct from old.lab_id then
    if not public.lab_can_write(old.lab_id)
       or new.lab_id is null
       or not public.lab_can_write(new.lab_id) then
      raise exception 'Shared lab items cannot be moved out of a lab you can edit'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_shared_lab_scope() from public, anon;

drop trigger if exists chemicals_protect_shared_lab on public.chemicals;
create trigger chemicals_protect_shared_lab
  before update on public.chemicals
  for each row execute function public.protect_shared_lab_scope();

drop trigger if exists apparatus_protect_shared_lab on public.apparatus;
create trigger apparatus_protect_shared_lab
  before update on public.apparatus
  for each row execute function public.protect_shared_lab_scope();

drop trigger if exists consumption_logs_protect_shared_lab on public.consumption_logs;
create trigger consumption_logs_protect_shared_lab
  before update on public.consumption_logs
  for each row execute function public.protect_shared_lab_scope();

-- Stock actions: the row owner, or a lab writer who is not a viewer.
-- Personal rows (lab_id null) still require user_id = auth.uid().
create or replace function public.apply_inventory_action(
  p_operation_id uuid,
  p_item_id uuid,
  p_item_type text,
  p_action text,
  p_amount numeric,
  p_note text default '',
  p_logged_at timestamptz default now()
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_previous numeric;
  v_next numeric;
  v_lab uuid;
  v_org uuid;
  v_log_id uuid;
  v_item jsonb;
  v_log jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_item_type not in ('chemical', 'apparatus') then
    raise exception 'Invalid item type';
  end if;
  if p_action not in ('consume', 'restock', 'breakage') then
    raise exception 'Invalid action';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;
  if p_item_type = 'chemical' and p_action = 'breakage' then
    raise exception 'Chemical breakage is not supported';
  end if;
  if p_item_type = 'apparatus' and p_action = 'consume' then
    raise exception 'Apparatus consumption is not supported';
  end if;

  select id into v_log_id
  from public.consumption_logs
  where user_id = v_user_id and operation_id = p_operation_id;

  if v_log_id is not null then
    select to_jsonb(l) into v_log from public.consumption_logs l where l.id = v_log_id;
    if p_item_type = 'chemical' then
      select to_jsonb(c) into v_item from public.chemicals c
      where c.id = p_item_id
        and public.can_mutate_inventory_item(v_user_id, c.user_id, c.lab_id);
    else
      select to_jsonb(a) into v_item from public.apparatus a
      where a.id = p_item_id
        and public.can_mutate_inventory_item(v_user_id, a.user_id, a.lab_id);
    end if;
    return jsonb_build_object('item', v_item, 'log', v_log, 'duplicate', true);
  end if;

  if p_item_type = 'chemical' then
    select quantity, lab_id, organization_id
      into v_previous, v_lab, v_org
    from public.chemicals
    where id = p_item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id)
    for update;
  else
    select quantity, lab_id, organization_id
      into v_previous, v_lab, v_org
    from public.apparatus
    where id = p_item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id)
    for update;
  end if;

  if not found then
    raise exception 'Item not found or not owned by the current user' using errcode = 'P0002';
  end if;

  if p_action in ('consume', 'breakage') then
    if v_previous < p_amount then
      raise exception 'Insufficient stock: only % available', v_previous using errcode = '22003';
    end if;
    v_next := v_previous - p_amount;
  else
    v_next := v_previous + p_amount;
  end if;

  if p_item_type = 'chemical' then
    update public.chemicals set quantity = v_next
    where id = p_item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id);
    select to_jsonb(c) into v_item from public.chemicals c
    where c.id = p_item_id
      and public.can_mutate_inventory_item(v_user_id, c.user_id, c.lab_id);
  else
    update public.apparatus set quantity = v_next
    where id = p_item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id);
    select to_jsonb(a) into v_item from public.apparatus a
    where a.id = p_item_id
      and public.can_mutate_inventory_item(v_user_id, a.user_id, a.lab_id);
  end if;

  v_log_id := gen_random_uuid();
  insert into public.consumption_logs (
    id, user_id, item_id, item_type, action, amount, note,
    logged_at, operation_id, organization_id, lab_id
  ) values (
    v_log_id, v_user_id, p_item_id, p_item_type, p_action, p_amount,
    coalesce(p_note, ''), coalesce(p_logged_at, now()), p_operation_id,
    v_org, v_lab
  );
  select to_jsonb(l) into v_log from public.consumption_logs l where l.id = v_log_id;

  return jsonb_build_object('item', v_item, 'log', v_log, 'duplicate', false);
end;
$$;

revoke all on function public.apply_inventory_action(uuid, uuid, text, text, numeric, text, timestamptz) from public;
revoke all on function public.apply_inventory_action(uuid, uuid, text, text, numeric, text, timestamptz) from anon;
grant execute on function public.apply_inventory_action(uuid, uuid, text, text, numeric, text, timestamptz) to authenticated;

create or replace function public.undo_inventory_action(
  p_operation_id uuid,
  p_log_id uuid,
  p_reason text default ''
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_log public.consumption_logs%rowtype;
  v_existing uuid;
  v_previous numeric;
  v_next numeric;
  v_item jsonb;
  v_reversal jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id into v_existing
  from public.inventory_reversals
  where user_id = v_user_id and operation_id = p_operation_id;

  if v_existing is not null then
    select to_jsonb(r) into v_reversal from public.inventory_reversals r where r.id = v_existing;
    return jsonb_build_object('item', null, 'reversal', v_reversal, 'duplicate', true);
  end if;

  -- Only the person who recorded the entry can undo it.
  select * into v_log
  from public.consumption_logs
  where id = p_log_id and user_id = v_user_id
  for update;

  if not found then
    return jsonb_build_object('item', null, 'reversal', null, 'duplicate', true, 'missing', true);
  end if;

  if v_log.item_type = 'chemical' then
    select quantity into v_previous
    from public.chemicals
    where id = v_log.item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id)
    for update;
  else
    select quantity into v_previous
    from public.apparatus
    where id = v_log.item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id)
    for update;
  end if;

  if not found then
    raise exception 'Item not found or not owned by the current user' using errcode = 'P0002';
  end if;

  if v_log.action = 'restock' then
    if v_previous < v_log.amount then
      raise exception 'Cannot undo: only % left of the % that was restocked', v_previous, v_log.amount
        using errcode = '22003';
    end if;
    v_next := v_previous - v_log.amount;
  else
    v_next := v_previous + v_log.amount;
  end if;

  if v_log.item_type = 'chemical' then
    update public.chemicals set quantity = v_next
    where id = v_log.item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id);
    select to_jsonb(c) into v_item from public.chemicals c
    where c.id = v_log.item_id
      and public.can_mutate_inventory_item(v_user_id, c.user_id, c.lab_id);
  else
    update public.apparatus set quantity = v_next
    where id = v_log.item_id
      and public.can_mutate_inventory_item(v_user_id, user_id, lab_id);
    select to_jsonb(a) into v_item from public.apparatus a
    where a.id = v_log.item_id
      and public.can_mutate_inventory_item(v_user_id, a.user_id, a.lab_id);
  end if;

  insert into public.inventory_reversals as r (
    user_id, item_id, item_type, action, amount,
    original_log_id, original_logged_at, original_note, reason, operation_id
  ) values (
    v_user_id, v_log.item_id, v_log.item_type, v_log.action, v_log.amount,
    v_log.id, v_log.logged_at, coalesce(v_log.note, ''), coalesce(p_reason, ''), p_operation_id
  )
  returning to_jsonb(r) into v_reversal;

  delete from public.consumption_logs where id = v_log.id and user_id = v_user_id;

  return jsonb_build_object('item', v_item, 'reversal', v_reversal, 'duplicate', false);
end;
$$;

revoke all on function public.undo_inventory_action(uuid, uuid, text) from public;
revoke all on function public.undo_inventory_action(uuid, uuid, text) from anon;
grant execute on function public.undo_inventory_action(uuid, uuid, text) to authenticated;

revoke all on function public.create_organization_with_lab(text, text, text, text) from public;
revoke all on function public.create_organization_with_lab(text, text, text, text) from anon;
grant execute on function public.create_organization_with_lab(text, text, text, text) to authenticated;

-- Ask PostgREST to reload schema
notify pgrst, 'reload schema';
