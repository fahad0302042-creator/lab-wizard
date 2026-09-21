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

## QR labels (QR-01, QR-02, QR-03)

Both shelves print labels. The shelf menu's *QR labels for all (A4 sheet)…* and the selection bar's *labels* open the same dialog: pick a grid — 40 per page (the web app's sheet, about 38 × 35 mm), 24 or 12 per page for larger equipment labels — see how many pages that makes, then *Print* (Android print dialog, which can also save a PDF) or *Share PDF*. Labels fill the sheet row by row so a partly used sheet can be run through again. Chemical labels encode the chemical's `qr_code` exactly like the web app (`labwizard:chemical:<qr_code>`), so both scanners read them; chemicals that never received a code are skipped with a note. Apparatus labels encode the row id (`labwizard:apparatus:<id>`), which survives renames and re-categorisation, and print the name, category, serial number and an eight-character short id so a person can match a damaged code by eye. The web app does not generate or scan apparatus codes; the Flutter scanner reads both.

Every item sheet shows its label as it will be exported — QR on the left, name and details on the right — with three buttons: *share image* renders a PNG (1200 px wide) and hands it to the system share sheet (save to Files, message it, or send it to a label-printer app), *PDF* shares a single 80 × 50 mm page, and *print* sends that page to the Android print dialog. The pure parts (`lib/features/labels/domain`) build the PDFs without any platform code, so `test/labels_test.dart` checks payloads, page counts and the generated documents on CI.

## Recent scans (SCAN-01)

Below the camera the scanner page lists the last codes read on this device — newest first, at most 30, kept in shared preferences under the signed-in user's id and never uploaded. Tapping a matched entry opens the item sheet again; entries whose item has since been deleted are shown as *removed*, and codes that did not match anything stay in the list as *not matched* so the payload can be inspected or copied (useful when a label was printed by something other than Lab Wizard). *clear* asks for confirmation and only forgets the history on this device. Matching itself lives in `resolveScan` (`lib/features/scanner/domain`): `labwizard:chemical:<qr_code>` and bare legacy codes look up chemicals by `qr_code`, `labwizard:apparatus:<id>` looks up apparatus by row id and never falls back to the chemical table.

## Batch scanning (SCAN-02)

Switch the scanner from *Single* to *Batch* to take stock of a shelf without leaving the camera: every recognised label is added to a running list (the camera never stops and no sheet opens), a label read again is counted — *already in batch ×2* — instead of being listed twice, a code that is still in view is not re-read for two seconds, and codes that match nothing are kept for the summary. *Finish (n)* pauses the camera and shows the summary: each item with its count and a tap into its sheet, the unmatched payloads, and either *Keep scanning* to add more or *Done* to clear the batch. Every read also lands in *recent scans*.

## Scan and act (SCAN-03)

In single mode a recognised label no longer drops you into the full item sheet. A compact sheet shows the name, current stock (and how many pieces are out on loan), one amount field — prefilled with the amount you used last time for that kind of item, whole pieces for apparatus — a row of one-tap amounts, and the actions: *Use*, *Restock*, *Damage*, and for apparatus with open loans *Return (n out)*, which asks which loan is coming back only when there is more than one. Success closes the sheet, shows the outcome over the camera ("Used 5 mL of Acetone · 45 mL left") and offers *Undo* in the snackbar; a wrong amount or too little stock is shown inline so the sheet stays open. *Open details* still leads to the full sheet. Entries made this way carry the note *via scanner* in the history, so they read the same in the web app.

## Product barcodes (SCAN-04)

Run `supabase/008_external_barcodes.sql` once: it adds a nullable `barcode` column to `chemicals` and `apparatus` (plus two partial indexes) and changes nothing else, so the web app is unaffected. The scanner's *Also read product barcodes* switch is off by default; when on, EAN-13/8, UPC-A/E, Code 128/39/93, ITF and Data Matrix codes are read as well as QR codes. A product code never opens anything by itself: the app only opens the item whose linked `barcode` equals the scanned text. Scanning a code nobody linked yet (in single mode) opens *link this code* — the payload and its format, a search over chemicals and apparatus, one tap to link — after which the quick-action sheet appears as for any recognised label. A code is linked to one item per account: choosing another item moves it, and linking to an item that already has a different code asks first. The link is written like any other edit (offline it waits in the outbox), the item sheet shows *Linked barcode …* with *unlink*, and unknown codes in *recent scans* offer *Link to item…* later. Third-party QR codes (a supplier's own label, for example) can be linked the same way.

## Selecting several items (BATCH-01/02/03/04, QR-01)

Long-press any card or row (or use the shelf menu → *select items…*) to enter selection mode. The bar at the bottom offers a batch restock with a separate amount and history entry per item, a batch low-stock threshold with an old → new preview, a batch storage location (chemicals) or category (apparatus) with the same preview — the field is decided by the shelf, so nothing is ever written to an item type that lacks it — QR labels for just the selected items (see *QR labels* above), and a guarded delete: unsynced items and offline devices are blocked, deleting five or more items requires typing `DELETE`, and every batch reports the rows that failed so they can be retried on their own.

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

## Incremental sync (SYNC-02)

Run `supabase/007_incremental_sync.sql` once and refreshes stop downloading the whole database. Each table keeps a per-user cursor (the last `(updated_at, id)` seen) in the local `sync_meta` table; a refresh asks PostgREST for rows after that cursor — keyset paging on `(updated_at, id)` in pages of 500, so identical timestamps from bulk inserts and the PostgREST 1000-row cap are both handled — re-fetching a two-minute overlap window so slow commits are never missed, then applies `deleted_rows` tombstones to the offline copy. The first refresh (or one with a cursor older than 120 days, since the server prunes tombstones after 180) is a paged full download that replaces each table while keeping rows still queued in the outbox and device-only reversals. Rows for another account are dropped defensively even though RLS never returns them, and every cursor is stored per user. The sync center shows how the last download went (*downloading only changes* vs *full download*, rows, pages, seconds) and has **Download everything again** as the escape hatch; servers without the migration are detected automatically (paged full downloads, with a hint naming the script).

## Background sync (SYNC-03)

The app syncs on its own in three situations. While it is open: when it returns to the foreground (skipped if a download finished under two minutes ago and nothing is queued) and when the connection comes back (`connectivity_plus`). While it is closed: an Android WorkManager job (`workmanager`) runs about every hour by default — Settings → *background sync* offers 1/3/6/12/24 hours, a Wi-Fi-only switch and the master toggle — sending the outbox and downloading changes with the battery-not-low constraint; leaving the app with queued changes also schedules a one-off *flush* job that runs as soon as a network is available and retries with exponential backoff. Jobs are cancelled on sign-out.

A WorkManager task runs in its own isolate. Two isolates refreshing the same Supabase session would rotate the refresh token underneath each other and sign the user out, so a task first looks for the app's main isolate over `IsolateNameServer` (`lib/features/sync/background/background_sync.dart`) and hands the work to it — the main isolate runs a normal refresh on its live session and records the outcome; only when nobody answers within ten seconds (the app process is gone) does the task start its own client from the persisted session. Either way the result (`3 changes sent · 2 updated, 1 removed`, `nothing to send`, `failed` + reason) is written to `sync_meta` and shown in the settings card and the sync center. Nothing runs twice: the main isolate skips a request while a sync is already running, and the outbox is idempotent (`operation_id`) in any case. Android decides the exact moment (Doze, battery savers); the cards say so.

## Conflict resolution (SYNC-04)

Edits are field-level and conditional. When you save an item the app compares the form with the copy it last saw, sends only the fields that actually changed, and asks PostgREST to apply them *only while those fields still hold the last-seen values* (`update … eq(field, previous)`). Anything changed elsewhere in the meantime — on the web app or another phone — therefore survives: unrelated fields are never touched, and a field that was changed on both sides is reported as a **conflict** instead of being overwritten. Live, the edit form shows a dialog with both values (*keep server values*, which still saves your other edits, or *overwrite with mine*). For a change that was queued offline, the sync center marks it *conflict*, explains it in plain words (`low-stock level is now 20 on the server (yours: 5)`) and offers the same choices plus *discard*. Array fields (hazard classes) are compared against a fresh copy before writing because they cannot be filtered reliably.

Stock is handled separately: quantities are never sent as absolute numbers when the atomic RPC exists, so two phones consuming the same bottle simply add up. When the server has less than a queued consume/damage entry needs, the RPC refuses it and the sync center explains the amounts and offers *apply what is left* (the queued entry and its local log are rewritten) or *discard*; an undo the server cannot honour any more and an item that was deleted on the server are explained and can only be removed. Conflicts are never retried blindly — *retry all* skips them — and they survive restarts (local database version 4 adds an outbox `conflict` column). Deployments without `001_flutter_safe_actions.sql` get the same protection on the fallback path: the quantity is written only while the server still has the value it was computed from and is otherwise rebased on the server's number. `test/sync_conflicts_test.dart` drives the real Supabase client against a small fake PostgREST to prove all of this.

## Sync center (SYNC-01)

Settings → *Sync center* (also reachable from the dashboard sync banner) lists every change waiting on the device with its attempts, last error and status. Connection problems keep a change `pending` and retry automatically; any other server error marks only that change as `failed` so other items keep syncing. Failed changes can be retried individually, all at once, or discarded — discarding rolls the offline copy back to what it was before the change.

## Signing

GitHub builds use `android/app/lab-wizard-github.jks`, a stable development-distribution key committed intentionally so phone-only testers can install future APKs as updates. Do not use this key for Play Store production. Configure private Play App Signing before publishing commercially.
