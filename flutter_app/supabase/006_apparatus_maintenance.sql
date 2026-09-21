-- Lab Wizard Flutter maintenance & calibration migration (GEAR-03)
-- ADDITIVE ONLY: one new table with its own RLS policies. Existing tables,
-- checks, policies and the web app's queries are untouched. Safe to run
-- repeatedly.
--
-- Each row is one service task for an apparatus: `kind` is 'maintenance' or
-- 'calibration'. A scheduled task has a `due_at` and no `completed_at`;
-- completing it fills `completed_at`, `performed_by`, `result` and `note`.
-- Recurring work simply schedules the next row when a task is completed.

create table if not exists public.apparatus_services (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  apparatus_id uuid not null references public.apparatus(id) on delete cascade,
  kind text not null default 'maintenance'
    check (kind in ('maintenance', 'calibration')),
  title text not null default '',
  note text not null default '',
  due_at timestamptz,
  completed_at timestamptz,
  performed_by text not null default '',
  result text not null default '',
  operation_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_services_user_item
  on public.apparatus_services(user_id, apparatus_id);

create index if not exists idx_services_due
  on public.apparatus_services(user_id, due_at)
  where completed_at is null;

-- A retried mobile insert must not create the task twice.
create unique index if not exists apparatus_services_user_operation_unique
  on public.apparatus_services (user_id, operation_id)
  where operation_id is not null;

alter table public.apparatus_services enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_services'
      and policyname = 'services_select_own'
  ) then
    create policy "services_select_own" on public.apparatus_services
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_services'
      and policyname = 'services_insert_own'
  ) then
    create policy "services_insert_own" on public.apparatus_services
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_services'
      and policyname = 'services_update_own'
  ) then
    create policy "services_update_own" on public.apparatus_services
      for update using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_services'
      and policyname = 'services_delete_own'
  ) then
    create policy "services_delete_own" on public.apparatus_services
      for delete using (auth.uid() = user_id);
  end if;
end
$$;

-- Ask PostgREST to pick up the new table immediately.
notify pgrst, 'reload schema';
