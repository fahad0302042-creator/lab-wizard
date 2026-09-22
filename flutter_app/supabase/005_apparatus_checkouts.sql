-- Lab Wizard Flutter apparatus checkout migration (GEAR-02)
-- ADDITIVE ONLY: one new table with its own RLS policies. Existing tables,
-- checks, policies and the web app's queries are untouched. Safe to run
-- repeatedly.
--
-- A checkout lends `quantity` pieces of an apparatus to a person. Returns
-- raise `returned_quantity`; when it reaches `quantity` the row is closed by
-- setting `returned_at`. Partial returns therefore never need extra rows.
-- Deleting an apparatus removes its checkouts (cascade), matching how the
-- web app deletes items.

create table if not exists public.apparatus_checkouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  apparatus_id uuid not null references public.apparatus(id) on delete cascade,
  quantity numeric not null default 1 check (quantity > 0),
  returned_quantity numeric not null default 0 check (returned_quantity >= 0),
  person text not null default '',
  note text not null default '',
  return_note text not null default '',
  checked_out_at timestamptz not null default now(),
  due_at timestamptz,
  returned_at timestamptz,
  operation_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_checkouts_user_item
  on public.apparatus_checkouts(user_id, apparatus_id);

create index if not exists idx_checkouts_open
  on public.apparatus_checkouts(user_id, due_at)
  where returned_at is null;

-- A retried mobile checkout must not be lent twice.
create unique index if not exists apparatus_checkouts_user_operation_unique
  on public.apparatus_checkouts (user_id, operation_id)
  where operation_id is not null;

alter table public.apparatus_checkouts enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_checkouts'
      and policyname = 'checkouts_select_own'
  ) then
    create policy "checkouts_select_own" on public.apparatus_checkouts
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_checkouts'
      and policyname = 'checkouts_insert_own'
  ) then
    create policy "checkouts_insert_own" on public.apparatus_checkouts
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_checkouts'
      and policyname = 'checkouts_update_own'
  ) then
    create policy "checkouts_update_own" on public.apparatus_checkouts
      for update using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'apparatus_checkouts'
      and policyname = 'checkouts_delete_own'
  ) then
    create policy "checkouts_delete_own" on public.apparatus_checkouts
      for delete using (auth.uid() = user_id);
  end if;
end
$$;

-- Ask PostgREST to pick up the new table immediately.
notify pgrst, 'reload schema';
