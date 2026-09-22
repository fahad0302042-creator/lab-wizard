-- Lab Wizard Flutter account deletion (ACCOUNT-03)
-- ADDITIVE ONLY: one function. No table, column, policy or trigger changes,
-- so the web app keeps working unchanged. Safe to run repeatedly.
--
-- public.delete_my_account() removes everything the calling user owns and
-- then the auth user itself. It can only ever act on auth.uid(), so a
-- signed-in person can delete their own account and nobody else's. The
-- Flutter app asks for the current password again before calling it.
--
-- Shared labs (010): rows with a lab_id and another lab member are reassigned
-- to that member first, because user_id is ON DELETE CASCADE and would
-- otherwise wipe the shared shelf. An organization this person created is
-- handed to another member, or deleted only when nobody else belongs to it.
-- Re-run this file after 010 so the function knows about those tables.
--
-- Retention: personal rows in chemicals, apparatus, consumption_logs and the
-- optional Flutter tables are deleted immediately (the sync tombstones written
-- by the delete triggers are removed too), then the auth.users row goes.
-- Supabase's own point-in-time/daily backups age out on the project's backup
-- schedule; nothing in the application keeps a copy.
--
-- If your project's postgres role is not allowed to delete from auth.users,
-- the function still removes personal data rows and then raises; delete the
-- user from Dashboard → Authentication → Users in that case.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_has_lab boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  v_has_lab := exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'chemicals'
      and column_name = 'lab_id'
  );

  -- Keep a shared organization when someone else still belongs to it.
  -- A sole-owned organization may leave with the account.
  if to_regclass('public.organizations') is not null then
    update public.organizations o
    set created_by = picked.user_id
    from (
      select distinct on (m.organization_id)
        m.organization_id,
        m.user_id
      from public.organization_members m
      where m.user_id <> v_user_id
      order by m.organization_id,
        case m.role
          when 'owner' then 0
          when 'admin' then 1
          when 'member' then 2
          else 3
        end,
        m.created_at
    ) picked
    where o.id = picked.organization_id
      and o.created_by = v_user_id;

    if exists (
      select 1
      from public.organizations o
      join public.organization_members m on m.organization_id = o.id
      where o.created_by = v_user_id
        and m.user_id <> v_user_id
    ) then
      raise exception
        'Transfer organization ownership before deleting this account'
        using errcode = '23503';
    end if;

    delete from public.organizations
    where created_by = v_user_id;
  end if;

  -- user_id is ON DELETE CASCADE. Leave shared rows pointing at a remaining
  -- member so deleting this account does not empty the lab shelf.
  if v_has_lab and to_regclass('public.lab_members') is not null then
    update public.chemicals c
    set user_id = (
      select lm.user_id
      from public.lab_members lm
      where lm.lab_id = c.lab_id
        and lm.user_id <> v_user_id
      order by case lm.role
        when 'manager' then 0
        when 'member' then 1
        else 2
      end
      limit 1
    )
    where c.user_id = v_user_id
      and c.lab_id is not null
      and exists (
        select 1 from public.lab_members lm
        where lm.lab_id = c.lab_id and lm.user_id <> v_user_id
      );

    update public.apparatus a
    set user_id = (
      select lm.user_id
      from public.lab_members lm
      where lm.lab_id = a.lab_id
        and lm.user_id <> v_user_id
      order by case lm.role
        when 'manager' then 0
        when 'member' then 1
        else 2
      end
      limit 1
    )
    where a.user_id = v_user_id
      and a.lab_id is not null
      and exists (
        select 1 from public.lab_members lm
        where lm.lab_id = a.lab_id and lm.user_id <> v_user_id
      );

    update public.consumption_logs l
    set user_id = (
      select lm.user_id
      from public.lab_members lm
      where lm.lab_id = l.lab_id
        and lm.user_id <> v_user_id
      order by case lm.role
        when 'manager' then 0
        when 'member' then 1
        else 2
      end
      limit 1
    )
    where l.user_id = v_user_id
      and l.lab_id is not null
      and exists (
        select 1 from public.lab_members lm
        where lm.lab_id = l.lab_id and lm.user_id <> v_user_id
      );
  end if;

  if to_regclass('public.apparatus_checkouts') is not null then
    update public.apparatus_checkouts c
    set user_id = a.user_id
    from public.apparatus a
    where c.apparatus_id = a.id
      and c.user_id = v_user_id
      and a.user_id <> v_user_id;
    delete from public.apparatus_checkouts where user_id = v_user_id;
  end if;
  if to_regclass('public.apparatus_services') is not null then
    update public.apparatus_services s
    set user_id = a.user_id
    from public.apparatus a
    where s.apparatus_id = a.id
      and s.user_id = v_user_id
      and a.user_id <> v_user_id;
    delete from public.apparatus_services where user_id = v_user_id;
  end if;
  if to_regclass('public.inventory_reversals') is not null then
    delete from public.inventory_reversals where user_id = v_user_id;
  end if;

  delete from public.consumption_logs where user_id = v_user_id;
  delete from public.apparatus where user_id = v_user_id;
  delete from public.chemicals where user_id = v_user_id;

  if to_regclass('public.deleted_rows') is not null then
    delete from public.deleted_rows where user_id = v_user_id;
  end if;

  delete from auth.users where id = v_user_id;
end;
$$;

revoke all on function public.delete_my_account() from public;
revoke all on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Deletes the calling user, their personal rows, and sole-owned organizations. Shared lab rows are reassigned first (Lab Wizard ACCOUNT-03).';

notify pgrst, 'reload schema';
