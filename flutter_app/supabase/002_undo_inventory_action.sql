-- Lab Wizard Flutter undo migration (UX-04)
-- ADDITIVE ONLY: one new table and one new function. Existing tables, checks,
-- policies and the web app's queries are untouched. Safe to run repeatedly.
--
-- Undoing an action mirrors what the web app already does (restore the
-- quantity and delete the log entry) but additionally keeps a record of the
-- reversal so the mobile audit trail can show "undone" entries.

create table if not exists public.inventory_reversals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null,
  item_type text not null check (item_type in ('chemical', 'apparatus')),
  action text not null check (action in ('consume', 'restock', 'breakage')),
  amount numeric not null default 0,
  original_log_id uuid,
  original_logged_at timestamptz,
  original_note text not null default '',
  reason text not null default '',
  operation_id uuid,
  reversed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_reversals_user on public.inventory_reversals(user_id);
create index if not exists idx_reversals_item on public.inventory_reversals(item_id);

-- A retried mobile undo must not apply twice.
create unique index if not exists inventory_reversals_user_operation_unique
  on public.inventory_reversals (user_id, operation_id)
  where operation_id is not null;

alter table public.inventory_reversals enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'inventory_reversals'
      and policyname = 'reversals_select_own'
  ) then
    create policy "reversals_select_own" on public.inventory_reversals
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'inventory_reversals'
      and policyname = 'reversals_insert_own'
  ) then
    create policy "reversals_insert_own" on public.inventory_reversals
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'inventory_reversals'
      and policyname = 'reversals_delete_own'
  ) then
    create policy "reversals_delete_own" on public.inventory_reversals
      for delete using (auth.uid() = user_id);
  end if;
end
$$;

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

  -- A retried mobile undo returns its first result instead of applying twice.
  select id into v_existing
  from public.inventory_reversals
  where user_id = v_user_id and operation_id = p_operation_id;

  if v_existing is not null then
    select to_jsonb(r) into v_reversal from public.inventory_reversals r where r.id = v_existing;
    return jsonb_build_object('item', null, 'reversal', v_reversal, 'duplicate', true);
  end if;

  select * into v_log
  from public.consumption_logs
  where id = p_log_id and user_id = v_user_id
  for update;

  if not found then
    -- The entry was already undone (the web app deletes entries when undoing)
    -- or belongs to a deleted item; nothing is left to reverse.
    return jsonb_build_object('item', null, 'reversal', null, 'duplicate', true, 'missing', true);
  end if;

  if v_log.item_type = 'chemical' then
    select quantity into v_previous
    from public.chemicals
    where id = v_log.item_id and user_id = v_user_id
    for update;
  else
    select quantity into v_previous
    from public.apparatus
    where id = v_log.item_id and user_id = v_user_id
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
    where id = v_log.item_id and user_id = v_user_id;
    select to_jsonb(c) into v_item from public.chemicals c
    where c.id = v_log.item_id and c.user_id = v_user_id;
  else
    update public.apparatus set quantity = v_next
    where id = v_log.item_id and user_id = v_user_id;
    select to_jsonb(a) into v_item from public.apparatus a
    where a.id = v_log.item_id and a.user_id = v_user_id;
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
