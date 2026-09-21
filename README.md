# Lab Wizard

Lab Wizard is a chemistry-lab inventory system with a notebook-inspired interface.

This repository now contains two clients that use the same Supabase data:

- The existing Next.js web app in the repository root.
- The Android-first Flutter app in [`flutter_app/`](flutter_app/README.md).

The Flutter work is isolated from the web source and does not require inventory to be entered again. Sign in to Android with the same account used on the web app.

## Install on Android without a PC

1. Open this repository in the GitHub app or your phone browser.
2. Open **Releases**.
3. Open the newest **Lab Wizard Android** release.
4. Download the file named `Lab-Wizard-Android-*.apk` under **Assets**.
5. Open the downloaded APK.
6. If Android asks, allow your browser or GitHub app to **install unknown apps**.
7. Install it and sign in with the same Lab Wizard email and password.

Future APKs use the same GitHub development signing key, so they can be installed as updates without deleting the app. Supabase remains the source of truth for synced data.

> The repository-visible signing key is intended only for direct GitHub development builds. A Play Store release must use private Play App Signing credentials.

## Automatic Android releases

[`.github/workflows/android-apk.yml`](.github/workflows/android-apk.yml) automatically:

1. installs Flutter,
2. verifies formatting,
3. runs static analysis and tests,
4. builds a signed universal Android APK,
5. uploads an Actions artifact, and
6. publishes the APK under GitHub Releases.

The workflow runs after Flutter changes are pushed to `main`. It can also be started from **Actions → Build Android APK → Run workflow**, which works from a phone browser.

## Data compatibility

The APK is compiled with the same public Supabase project configuration as the web app. Supabase Row Level Security restricts each signed-in user to their own rows. The public anonymous API key is not a service-role secret and is already shipped to both clients.

The Flutter app keeps a per-user SQLite cache and pending-operation outbox. Cached private data is cleared when the user signs out.

For atomic, retry-safe inventory updates, apply the optional additive migration at:

[`flutter_app/supabase/001_flutter_safe_actions.sql`](flutter_app/supabase/001_flutter_safe_actions.sql)

The migration adds columns, constraints, an idempotency index, and an RPC function. It does not remove or rename anything used by the web app. Until it is installed, Flutter uses a compatibility flow against the existing schema.

Undo support on Android (UX-04) has its own optional additive migration, [`flutter_app/supabase/002_undo_inventory_action.sql`](flutter_app/supabase/002_undo_inventory_action.sql). It adds an `inventory_reversals` table (RLS: own rows only) and an idempotent `undo_inventory_action` RPC. Undo behaves exactly like the web app's undo — the quantity is restored and the log entry removed — and additionally records the reversal so the mobile history can show it. Without the migration the app falls back to the web-parity flow and keeps the reversal note on the device only.

Chemical metadata on Android (DATA-01) uses [`flutter_app/supabase/003_chemical_metadata.sql`](flutter_app/supabase/003_chemical_metadata.sql): six nullable columns on `chemicals` (`supplier`, `cas_number`, `concentration`, `location`, `expiry_date`, `hazard_classes`) and one partial index. Existing rows and the web app's inserts stay valid because every column is optional; the web app simply ignores the extra columns. Until the script is run, the app hides nothing but tells you the database needs the update if you try to save those details.

Apparatus metadata (GEAR-01) follows the same pattern with [`flutter_app/supabase/004_apparatus_metadata.sql`](flutter_app/supabase/004_apparatus_metadata.sql): six nullable columns on `apparatus` (`serial_number`, `condition`, `assigned_to`, `location`, `purchase_date`, `warranty_until`).

Apparatus checkouts (GEAR-02) add one new table with [`flutter_app/supabase/005_apparatus_checkouts.sql`](flutter_app/supabase/005_apparatus_checkouts.sql): `apparatus_checkouts` (own rows only via RLS, `on delete cascade` from `apparatus`, unique per queued operation so a retried mobile checkout is never lent twice). Loans do not modify `apparatus.quantity`, so the web app's numbers and queries are unaffected; the table is simply invisible to it.

Maintenance and calibration (GEAR-03) add [`flutter_app/supabase/006_apparatus_maintenance.sql`](flutter_app/supabase/006_apparatus_maintenance.sql): an `apparatus_services` table (kind `maintenance` / `calibration`, due and completion timestamps, performer, result, note) with the same own-rows RLS, cascade and retry-safe unique operation id. Again nothing existing changes and the web app never reads the table.

Incremental sync (SYNC-02) adds [`flutter_app/supabase/007_incremental_sync.sql`](flutter_app/supabase/007_incremental_sync.sql): an `updated_at timestamptz not null default now()` column on `chemicals`, `apparatus`, `consumption_logs` and the optional Flutter tables (existing rows are back-filled with the migration time), a `before update` trigger that keeps it current, and a `deleted_rows` tombstone table (own rows only via RLS) filled by `after delete` triggers. The web app is unaffected: its inserts get the default, its updates go through the trigger and its deletes leave a tombstone without any code change. Phones then download only rows changed since their cursor plus deletions, in pages of 500; without the migration they fall back to paged full downloads.

External barcodes (SCAN-04) add [`flutter_app/supabase/008_external_barcodes.sql`](flutter_app/supabase/008_external_barcodes.sql): a nullable `barcode text` column on `chemicals` and `apparatus` with partial indexes per user. The web app never reads or writes it; the Flutter scanner only opens an item whose `barcode` equals a scanned product code after a person linked the two explicitly.

Account deletion (ACCOUNT-03) adds [`flutter_app/supabase/009_account_deletion.sql`](flutter_app/supabase/009_account_deletion.sql): one `public.delete_my_account()` function (SECURITY DEFINER, executable by `authenticated` only) that deletes the caller's own rows in every table and then the caller's `auth.users` row. No table, policy or trigger changes; the web app is unaffected.

Background sync (SYNC-03) needs no database change: it reuses the incremental download and the idempotent outbox from an Android WorkManager job.

Conflict resolution (SYNC-04) needs no database change either: the phone sends only the fields it changed, as a compare-and-set on their last-seen values (plain PostgREST filters), so an edit made in the web app in the meantime is never overwritten silently — the phone shows the conflict and asks.

## Improvement program

The post-1.0.4 Android improvement checklist lives in [`FLUTTER_IMPROVEMENT_ROADMAP.md`](FLUTTER_IMPROVEMENT_ROADMAP.md). Feature branches are verified by [`.github/workflows/flutter-branch-ci.yml`](.github/workflows/flutter-branch-ci.yml), which formats and auto-fixes the Dart code on the runner, analyzes, tests, and uploads a signed APK artifact for phone verification.

## Web app

See [`SUPABASE_SETUP.md`](SUPABASE_SETUP.md) for the original web setup notes. The web app source remains in `src/`.
