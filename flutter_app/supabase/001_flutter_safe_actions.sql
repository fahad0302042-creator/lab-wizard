-- Lab Wizard Flutter compatibility migration
-- ADDITIVE ONLY: existing web inserts/selects continue to work unchanged.
-- Run in the Supabase SQL editor before relying on queued/offline actions.
--
-- If supabase/010_multi_lab_organizations.sql has already been applied,
-- re-run that file after this one. This script's apply_inventory_action is
-- owner-only; 010 replaces it so a lab writer can act on a shared row.

alter table public.chemicals
  add column if not exists low_stock_threshold numeric not null default 0;

alter table public.apparatus
  add column if not exists low_stock_threshold numeric not null default 0;

alter table public.consumption_logs
  add column if not exists operation_id uuid;

create unique index if not exists consumption_logs_user_operation_unique
  on public.consumption_logs (user_id, operation_id)
  where operation_id is not null;

-- NOT VALID preserves any historical bad rows while enforcing the rules for new writes.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chemicals_quantity_nonnegative') then
    alter table public.chemicals
      add constraint chemicals_quantity_nonnegative check (quantity >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'apparatus_quantity_nonnegative') then
    alter table public.apparatus
      add constraint apparatus_quantity_nonnegative check (quantity >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'consumption_logs_amount_positive') then
    alter table public.consumption_logs
      add constraint consumption_logs_amount_positive check (amount > 0) not valid;
  end if;
end
$$;

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

  -- A retried mobile operation returns its first result instead of applying twice.
  select id into v_log_id
  from public.consumption_logs
  where user_id = v_user_id and operation_id = p_operation_id;

  if v_log_id is not null then
    select to_jsonb(l) into v_log from public.consumption_logs l where l.id = v_log_id;
    if p_item_type = 'chemical' then
      select to_jsonb(c) into v_item from public.chemicals c
      where c.id = p_item_id and c.user_id = v_user_id;
    else
      select to_jsonb(a) into v_item from public.apparatus a
      where a.id = p_item_id and a.user_id = v_user_id;
    end if;
    return jsonb_build_object('item', v_item, 'log', v_log, 'duplicate', true);
  end if;

  if p_item_type = 'chemical' then
    select quantity into v_previous
    from public.chemicals
    where id = p_item_id and user_id = v_user_id
    for update;
  else
    select quantity into v_previous
    from public.apparatus
    where id = p_item_id and user_id = v_user_id
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
    where id = p_item_id and user_id = v_user_id;
    select to_jsonb(c) into v_item from public.chemicals c
    where c.id = p_item_id and c.user_id = v_user_id;
  else
    update public.apparatus set quantity = v_next
    where id = p_item_id and user_id = v_user_id;
    select to_jsonb(a) into v_item from public.apparatus a
    where a.id = p_item_id and a.user_id = v_user_id;
  end if;

  v_log_id := gen_random_uuid();
  insert into public.consumption_logs (
    id, user_id, item_id, item_type, action, amount, note,
    logged_at, operation_id
  ) values (
    v_log_id, v_user_id, p_item_id, p_item_type, p_action, p_amount,
    coalesce(p_note, ''), coalesce(p_logged_at, now()), p_operation_id
  );
  select to_jsonb(l) into v_log from public.consumption_logs l where l.id = v_log_id;

  return jsonb_build_object('item', v_item, 'log', v_log, 'duplicate', false);
end;
$$;

revoke all on function public.apply_inventory_action(uuid, uuid, text, text, numeric, text, timestamptz) from public;
revoke all on function public.apply_inventory_action(uuid, uuid, text, text, numeric, text, timestamptz) from anon;
grant execute on function public.apply_inventory_action(uuid, uuid, text, text, numeric, text, timestamptz) to authenticated;
