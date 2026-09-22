-- Lab Wizard Flutter chemical metadata migration (DATA-01)
-- ADDITIVE ONLY: six nullable columns on public.chemicals plus one partial
-- index. No existing column, check constraint or policy is touched, so rows
-- created by the web app (which never sends these columns) stay valid and
-- the web app keeps working unchanged. Safe to run repeatedly.
--
-- Column notes
--   supplier        free text ("Sigma-Aldrich")
--   cas_number      CAS Registry Number as text ("7732-18-5"); the app
--                   validates the check digit, the database does not
--   concentration   free text ("37%", "0.1 M")
--   location        storage location ("Cabinet B, shelf 2")
--   expiry_date     calendar date, no time zone
--   hazard_classes  GHS pictogram codes (GHS01..GHS09) as a text array

alter table public.chemicals
  add column if not exists supplier text,
  add column if not exists cas_number text,
  add column if not exists concentration text,
  add column if not exists location text,
  add column if not exists expiry_date date,
  add column if not exists hazard_classes text[];

-- Expiry queries are always per user and only care about dated rows.
create index if not exists idx_chemicals_user_expiry
  on public.chemicals(user_id, expiry_date)
  where expiry_date is not null;

comment on column public.chemicals.hazard_classes is
  'GHS pictogram codes such as GHS02 (flammable). Optional; set by the Flutter app.';

-- Ask PostgREST to pick up the new columns immediately instead of waiting
-- for its periodic schema cache reload.
notify pgrst, 'reload schema';
