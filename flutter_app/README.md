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

## Checkouts (GEAR-02)

Run `supabase/005_apparatus_checkouts.sql` to add the `apparatus_checkouts` table (own rows only, cascades when an apparatus is deleted; nothing existing is touched). An apparatus item sheet then shows *checkouts*: how many of the pieces are available, who has the rest and since when, a due date with overdue copy, and a **Check out** button (disabled once every piece is out). Checking out asks for a person (recent names are one tap away), a whole number of pieces up to what is available, an optional due date (YYYY-MM-DD, picker or quick chips) and a note; returning takes back some or all pieces with a note and closes the loan when everything is in. Loans never change the stock count — the shelf simply marks *N out* (red with *overdue* when late) — so the web app's quantities stay exactly as they are. Both actions work offline through the outbox (`checkout_apparatus` / `return_apparatus`) and can be discarded from the sync center; a discarded loan also drops any return queued for it.

## Maintenance and calibration (GEAR-03)

Run `supabase/006_apparatus_maintenance.sql` to add the `apparatus_services` table (own rows only, cascades with the apparatus). The apparatus item sheet gains *maintenance & calibration*: **Schedule** creates a task (maintenance or calibration, optional title such as "Annual calibration", due date via YYYY-MM-DD / picker / 1-3-6-12-month chips, note); open tasks are listed soonest first with *due in N days*, *due today* or *overdue by N days* copy and a **done** button. Completing records the date (today or earlier), who performed it, a result (pass / adjusted / fail / serviced or free text) and a note, and can schedule the next task of the same kind in one step so recurring intervals never need re-typing. The shelf marks *calibration overdue* / *maintenance due* (due within 14 days) on cards and compact rows. Both actions work offline (`schedule_service` / `complete_service` outbox entries) and can be discarded from the sync center with a full rollback.

## Apparatus history (GEAR-04)

The apparatus item sheet's *history* now mixes loans, returns, scheduled and completed tasks with uses, damage and undo notes (latest eight). **Full history & report** opens a timeline screen with a summary card (in stock / out, damage entries, loans and late returns, tasks, last calibration, last maintenance, next due), *all / stock / loans / service* filters and a share button that writes the whole timeline as a plain-text report (`lab-wizard-<item>-history.txt`) — plain text on purpose, so notes can never be interpreted as spreadsheet formulas. Everything is computed from the cached data, so it works offline.

## Notifications (NOTIFY-01/02/03/04)

Settings → *notifications* holds a master switch (asks for the Android 13+ permission; when it is blocked the card says so and offers *open system settings*), one switch per topic — low/empty stock, chemical expiry, apparatus returns, maintenance & calibration, sync problems, weekly summary — plus the expiry and service warning windows, the reminder hour and a *send a test notification* button. Everything is local: preferences live in `SharedPreferences`, alerts are computed on the phone from the cached inventory, and nothing is sent to a server.

Two mechanisms work together. **Alerts** (`buildAlerts`) describe what needs attention *now* — empty and low stock, expired and expiring chemicals, overdue loans, overdue and due-soon service tasks, failed outbox changes — and are shown as notifications at most once per day per subject (a persisted `id → date` map); more than three new alerts at once collapse into a single digest. **Planned reminders** (`planReminders`) are scheduled ahead with `flutter_local_notifications` (inexact alarms, restored after reboot by the plugin's boot receiver) so loan due times, service due dates, expiry dates and the weekly summary arrive even when the app is closed; the plan is rebuilt after every data change. Tapping a notification opens the item sheet, the sync center or the *needs attention* screen (dashboard → *reminders* card), which lists the same alerts and the weekly digest text. Without the permission, or with the master switch off, the in-app list keeps working.

## CSV import (IMPORT-01)

Settings → *backup & import* → **Import CSV** opens the system file picker (no storage permission needed). The app's own export imports as-is; other files are mapped column by column with automatic header guesses, a *first row is a header* switch and a shelf selector (chemicals, apparatus, or a `type` column). Every row is validated before anything is written — missing names, non-numeric or negative amounts, fractional apparatus counts, bad CAS numbers and unreadable dates are errors; unknown units/categories and missing units fall back with a warning — and rows matching an existing item are flagged as duplicates and skipped unless *import duplicates too* is on. The import runs row by row (offline rows go through the outbox like any other add), and the finished screen lists every skipped or failed line with its reason and can share the report as a text file.

## Sync center (SYNC-01)

Settings → *Sync center* (also reachable from the dashboard sync banner) lists every change waiting on the device with its attempts, last error and status. Connection problems keep a change `pending` and retry automatically; any other server error marks only that change as `failed` so other items keep syncing. Failed changes can be retried individually, all at once, or discarded — discarding rolls the offline copy back to what it was before the change.

## Signing

GitHub builds use `android/app/lab-wizard-github.jks`, a stable development-distribution key committed intentionally so phone-only testers can install future APKs as updates. Do not use this key for Play Store production. Configure private Play App Signing before publishing commercially.
