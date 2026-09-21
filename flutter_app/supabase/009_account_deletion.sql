-- Lab Wizard Flutter account deletion (ACCOUNT-03)
-- ADDITIVE ONLY: one function. No table, column, policy or trigger changes,
-- so the web app keeps working unchanged. Safe to run repeatedly.
--
-- public.delete_my_account() removes everything the calling user owns and
-- then the auth user itself. It can only ever act on auth.uid(), so a
-- signed-in person can delete their own account and nobody else's. The
-- Flutter app asks for the current password again before calling it.
--
-- Retention: rows in chemicals, apparatus, consumption_logs and the optional
-- Flutter tables are deleted immediately (the sync tombstones written by the
-- delete triggers are removed too), then the auth.users row goes, which
-- cascades anything left. Supabase's own point-in-time/daily backups age
-- out on the project's backup schedule; nothing in the application keeps a
-- copy.
--
-- If your project's postgres role is not allowed to delete from auth.users,
-- the function still removes all data rows and then raises; delete the user
-- from Dashboard → Authentication → Users in that case.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Optional Flutter tables first (they reference apparatus / the user).
  if to_regclass('public.apparatus_services') is not null then
    delete from public.apparatus_services where user_id = v_user_id;
  end if;
  if to_regclass('public.apparatus_checkouts') is not null then
    delete from public.apparatus_checkouts where user_id = v_user_id;
  end if;
  if to_regclass('public.inventory_reversals') is not null then
    delete from public.inventory_reversals where user_id = v_user_id;
  end if;

  delete from public.consumption_logs where user_id = v_user_id;
  delete from public.apparatus where user_id = v_user_id;
  delete from public.chemicals where user_id = v_user_id;

  -- Tombstones written by the delete triggers above (SYNC-02) and any older
  -- ones: nothing is left to sync for this account.
  if to_regclass('public.deleted_rows') is not null then
    delete from public.deleted_rows where user_id = v_user_id;
  end if;

  -- Finally the account itself; cascades clean up anything else.
  delete from auth.users where id = v_user_id;
end;
$$;

revoke all on function public.delete_my_account() from public;
revoke all on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Deletes all data of the calling user and the auth user (Lab Wizard ACCOUNT-03).';

notify pgrst, 'reload schema';
