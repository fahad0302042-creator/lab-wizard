-- Lab Wizard Flutter incremental sync migration (SYNC-02)
-- ADDITIVE ONLY: one nullable-by-default column (`updated_at`, filled with
-- now() for existing rows), two small trigger functions, one tombstone table
-- with its own RLS policy, and indexes. No existing column, check, policy or
-- web app query changes. Safe to run repeatedly.
--
-- What it enables: instead of downloading every row on each refresh, the
-- phone asks for rows whose `updated_at` is newer than its cursor and for
-- deletions recorded in `deleted_rows` since that cursor. The web app keeps
-- working as before: its inserts get `updated_at` from the default, its
-- updates from the trigger, and its deletes leave a tombstone automatically.
--
-- Tombstones older than 180 days are pruned opportunistically (whenever a
-- row of the same user is deleted). The app performs a full download when
-- its cursor is older than 120 days, so nothing is ever missed.

-- Keeps `updated_at` current on every UPDATE.
create or replace function public.lab_wizard_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end
$$;

-- One row per deleted record so phones can drop it from their offline copy.
create table if not exists public.deleted_rows (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  table_name text not null,
  row_id uuid not null,
  deleted_at timestamptz not null default now()
);

create index if not exists idx_deleted_rows_user_time
  on public.deleted_rows(user_id, deleted_at, id);

alter table public.deleted_rows enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'deleted_rows'
      and policyname = 'deleted_rows_select_own'
  ) then
    create policy "deleted_rows_select_own" on public.deleted_rows
      for select using (auth.uid() = user_id);
  end if;
end
$$;

-- Writes the tombstone. SECURITY DEFINER so cascades that run without a
-- signed-in user (for example an account deletion) still succeed; the
-- function only ever inserts the deleted row's own user_id.
create or replace function public.lab_wizard_record_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.deleted_rows (user_id, table_name, row_id)
  values (old.user_id, tg_table_name, old.id);
  -- Opportunistic housekeeping for this user only.
  delete from public.deleted_rows
  where user_id = old.user_id
    and deleted_at < now() - interval '180 days';
  return old;
end
$$;

-- Apply to every table the app downloads. Optional tables from earlier
-- migrations are skipped when they do not exist yet; re-run this script
-- after installing them.
do $$
declare
  t text;
begin
  foreach t in array array[
    'chemicals',
    'apparatus',
    'consumption_logs',
    'inventory_reversals',
    'apparatus_checkouts',
    'apparatus_services'
  ]
  loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;
    execute format(
      'alter table public.%I add column if not exists updated_at timestamptz not null default now()',
      t
    );
    execute format(
      'create index if not exists %I on public.%I (user_id, updated_at, id)',
      'idx_' || t || '_user_updated',
      t
    );
    execute format('drop trigger if exists %I on public.%I', t || '_touch_updated_at', t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.lab_wizard_touch_updated_at()',
      t || '_touch_updated_at',
      t
    );
    execute format('drop trigger if exists %I on public.%I', t || '_record_deletion', t);
    execute format(
      'create trigger %I after delete on public.%I for each row execute function public.lab_wizard_record_deletion()',
      t || '_record_deletion',
      t
    );
  end loop;
end
$$;

-- Ask PostgREST to pick up the new table and columns immediately.
notify pgrst, 'reload schema';
