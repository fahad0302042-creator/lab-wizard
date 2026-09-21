# Lab Wizard for Android

A Flutter client for the existing Lab Wizard Supabase inventory. It uses the same accounts, chemicals, apparatus, and consumption logs as the web app.

## Included in the first build

- Existing Supabase email/password authentication
- Per-user SQLite offline cache and pending-operation outbox
- Animated notebook dashboard
- Chemical and apparatus search/filter lists
- Swipe-to-consume, swipe-to-restock, and breakage workflows
- Low/out-of-stock indicators
- Animated quantities, progress bars, headings, lists, and transitions
- QR scanner with moving scan line, flashlight, camera switch, and manual search
- Item details, QR label display, notes, and activity history
- Monthly reports, charts, and PDF sharing
- CSV inventory backup with spreadsheet-formula protection
- Light, dark, system, and reduced-motion preferences
- Additive transactional Supabase RPC migration
- Automatic signed APK publishing through GitHub Actions

## Data

`config/production.json` contains the public Supabase URL and anonymous client key used by the existing web app. It is included at compile time by GitHub Actions. The key is public by design; authorization is enforced by Supabase authentication and Row Level Security.

The app never uses a service-role key.

## Local commands

A PC is not required for normal installation. These commands are only for developers:

```bash
flutter pub get
flutter test
flutter analyze
flutter run --dart-define-from-file=config/production.json
flutter build apk --release --dart-define-from-file=config/production.json
```

## Architecture

```text
lib/
  app/                 Riverpod providers and application root
  core/
    config/            compile-time configuration
    database/          SQLite cache and outbox
    theme/             modern notebook design system
    widgets/           paper, cards, stock and motion components
  features/
    auth/
    home/
    inventory/
    scanner/
    reports/
    settings/
```

Supabase remains the remote source of truth. Local records are keyed by authenticated user ID and are loaded only after a valid Supabase session exists.

## Transaction-safe actions

Run `supabase/001_flutter_safe_actions.sql` in the Supabase SQL Editor when ready. It installs an idempotent `apply_inventory_action` RPC that locks the inventory row and records the quantity change and log in one PostgreSQL transaction. Existing web behavior remains compatible.

Without this migration, the mobile app automatically falls back to the existing tables so current data remains usable.

## Undo (UX-04)

Run `supabase/002_undo_inventory_action.sql` to add the `inventory_reversals` table and the idempotent `undo_inventory_action` RPC. Undoing a consume/restock/damage restores the quantity and deletes the log entry (the same thing the web app's undo does) and stores a reversal record that the item history shows as an "undone" entry. Changes that are still queued on the device are simply cancelled. Only entries recorded in the last 7 days can be undone, and a restock cannot be undone once that stock has been used. Without the migration the app performs the web-parity undo and keeps the reversal note locally.

## Duplicate warnings and remembered form choices (DUP-01, FORM-01)

While you type a new item, the add sheet compares the normalized name (case, spacing and punctuation ignored), formula and category with what is already on the shelf and shows the matches inline with *view* and *add anyway* links. Saving is blocked until a match is either opened or waved through. The add and action sheets also start from the unit, category, low-stock level and action amount you used last time on this device (per signed-in user); both prefills can be switched off or forgotten in Settings → *form memory*.

## Chemical details, expiry and hazards (DATA-01, DATA-02)

Run `supabase/003_chemical_metadata.sql` to add optional `supplier`, `cas_number`, `concentration`, `location`, `expiry_date` and `hazard_classes` columns to `chemicals`. All columns are nullable, so rows created by the web app or before the migration stay valid and the web app is unaffected. The add/edit sheets gain a collapsible *more details* section (CAS numbers are check-digit validated, hazards are GHS01–GHS09 chips, expiry is a calendar date). Chemicals that are expired or expire within 30 days get a badge on the shelf and an *expiring* filter; the item sheet shows the metadata, a plain-language expiry line and hazard chips. The CSV export includes the new columns. Metadata columns are only sent to the server when they are filled in or changed, and the app explains that the database needs the script if it is missing.

## Selecting several items (BATCH-01/02/03/04, QR-01)

Long-press any card or row (or use the shelf menu → *select items…*) to enter selection mode. The bar at the bottom offers a batch restock with a separate amount and history entry per item, a batch low-stock threshold with an old → new preview, a batch storage location (chemicals) or category (apparatus) with the same preview — the field is decided by the shelf, so nothing is ever written to an item type that lacks it — QR labels for just the selected chemicals, and a guarded delete: unsynced items and offline devices are blocked, deleting five or more items requires typing `DELETE`, and every batch reports the rows that failed so they can be retried on their own.

## Apparatus details (GEAR-01)

Run `supabase/004_apparatus_metadata.sql` to add optional `serial_number`, `condition`, `assigned_to`, `location`, `purchase_date` and `warranty_until` columns to `apparatus` (all nullable, additive, web app unaffected). The apparatus add/edit sheets get the same collapsible *more details* section as chemicals (condition is offered as good / fair / needs repair / retired), the item sheet shows the details with warranty copy, shelf rows mark items that need repair, are assigned to someone or whose warranty is ending, and the fields are searchable, exported and importable.

## CSV import (IMPORT-01)

Settings → *backup & import* → **Import CSV** opens the system file picker (no storage permission needed). The app's own export imports as-is; other files are mapped column by column with automatic header guesses, a *first row is a header* switch and a shelf selector (chemicals, apparatus, or a `type` column). Every row is validated before anything is written — missing names, non-numeric or negative amounts, fractional apparatus counts, bad CAS numbers and unreadable dates are errors; unknown units/categories and missing units fall back with a warning — and rows matching an existing item are flagged as duplicates and skipped unless *import duplicates too* is on. The import runs row by row (offline rows go through the outbox like any other add), and the finished screen lists every skipped or failed line with its reason and can share the report as a text file.

## Sync center (SYNC-01)

Settings → *Sync center* (also reachable from the dashboard sync banner) lists every change waiting on the device with its attempts, last error and status. Connection problems keep a change `pending` and retry automatically; any other server error marks only that change as `failed` so other items keep syncing. Failed changes can be retried individually, all at once, or discarded — discarding rolls the offline copy back to what it was before the change.

## Signing

GitHub builds use `android/app/lab-wizard-github.jks`, a stable development-distribution key committed intentionally so phone-only testers can install future APKs as updates. Do not use this key for Play Store production. Configure private Play App Signing before publishing commercially.
