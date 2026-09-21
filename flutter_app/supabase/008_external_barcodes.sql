-- Lab Wizard Flutter external barcode migration (SCAN-04)
-- ADDITIVE ONLY: one nullable text column on public.chemicals and one on
-- public.apparatus plus two partial indexes. No existing column, check
-- constraint or policy is touched, so rows created by the web app (which
-- never sends the column) stay valid and the web app keeps working
-- unchanged. Safe to run repeatedly.
--
-- Column notes
--   barcode   the raw text of a product barcode (EAN-13, UPC, Code 128 …)
--             or of a third-party QR code that a person explicitly linked
--             to this item from the Flutter scanner. Lab Wizard never
--             matches such codes on its own; a scan only opens an item whose
--             barcode equals the scanned text. One code should be linked to
--             a single item per account; the app moves a link on request
--             instead of allowing duplicates, the database does not enforce
--             it so that imports and the web app can never fail on it.

alter table public.chemicals
  add column if not exists barcode text;

alter table public.apparatus
  add column if not exists barcode text;

-- Lookups are always per user and only care about linked rows.
create index if not exists idx_chemicals_user_barcode
  on public.chemicals(user_id, barcode)
  where barcode is not null;

create index if not exists idx_apparatus_user_barcode
  on public.apparatus(user_id, barcode)
  where barcode is not null;

comment on column public.chemicals.barcode is
  'Product barcode or third-party code explicitly linked from the Flutter scanner (SCAN-04). Optional.';
comment on column public.apparatus.barcode is
  'Product barcode or third-party code explicitly linked from the Flutter scanner (SCAN-04). Optional.';

-- Ask PostgREST to pick up the new columns immediately instead of waiting
-- for its periodic schema cache reload.
notify pgrst, 'reload schema';
