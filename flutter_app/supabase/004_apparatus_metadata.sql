-- Lab Wizard Flutter apparatus metadata migration (GEAR-01)
-- ADDITIVE ONLY: six nullable columns on public.apparatus. No existing
-- column, check constraint or policy is touched, so rows created by the web
-- app (which never sends these columns) stay valid and the web app keeps
-- working unchanged. Safe to run repeatedly.
--
-- Column notes
--   serial_number   free text, e.g. manufacturer serial or asset tag
--   condition       free text; the app offers good / fair / needs repair /
--                   retired
--   assigned_to     person or bench currently responsible for the item
--   location        storage location ("Bench 3", "Store room")
--   purchase_date   calendar date, no time zone
--   warranty_until  calendar date, no time zone

alter table public.apparatus
  add column if not exists serial_number text,
  add column if not exists condition text,
  add column if not exists assigned_to text,
  add column if not exists location text,
  add column if not exists purchase_date date,
  add column if not exists warranty_until date;

create index if not exists idx_apparatus_user_warranty
  on public.apparatus(user_id, warranty_until)
  where warranty_until is not null;

comment on column public.apparatus.condition is
  'Free text condition; the Flutter app offers good, fair, needs repair and retired.';

-- Ask PostgREST to pick up the new columns immediately.
notify pgrst, 'reload schema';
