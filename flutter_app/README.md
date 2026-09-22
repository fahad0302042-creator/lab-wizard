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

## Report ranges (REPORT-01)

The report page is no longer tied to a calendar month. Chips switch between *7 days*, *30 days*, *month* (with the previous/next arrows) and *custom*; tapping the range itself opens a date-range picker. A range is a run of inclusive local calendar days: a log stamped 23:59 on the last day is in, one stamped 00:00 the day after is out, whatever zone the entry was written in, and day arithmetic is done on dates rather than 24-hour spans so daylight-saving days do not shift anything. The card shows the label, the exact dates and the day count; the activity chart shows one bar per day up to 62 days and one per week beyond that (tap a bar for the exact period); the PDF file name and title carry the range.

## Trends (REPORT-02)

The three metric cards count usage actions, restocks and damage separately and, under the count, sum the quantities per unit — *350 mL · 20 g* — so grams and millilitres are never added together (apparatus is always pieces). Each card compares its count with the period of equal length just before the selected one (the previous calendar month for month ranges): *+50% vs before* with an arrow coloured good-or-bad for that action, *none before* when the earlier period had nothing (no percentage against zero), and a note under the cards names the exact comparison dates.

## Run-out estimates (REPORT-03)

The *run-out estimates* card projects when each chemical (or apparatus, in pieces) reaches zero, and shows the reasoning with every number: *~26 days · 17 Oct — 40 mL left; 3 uses totalling 30 mL over the last 20 days, about 1.5 mL per day*. An estimate exists only with adequate history — at least three uses spread over at least seven days within the last 90 days; only *use* entries count, restocks and damage do not — and items that fall short are counted in one line (*4 items have too little history…*) rather than guessed at. The list is sorted soonest first, coloured at seven and thirty days, says *today* or *already out* when it applies, and always looks at the last 90 days regardless of the range chosen above, so a report about a past month never "predicts" the past.

## Expiry and apparatus views (REPORT-04)

Below the run-out estimates the report page shows what needs attention on the selected shelf. Chemicals: *expiry* — expired first, then anything expiring within 30 days, soonest first, with the exact date and *expired 40 days ago* / *in 3 days*, and a footer counting items that expire later or have no date — and *damage*, the breakage recorded in the selected range grouped per item (incidents, total amount, last date). Apparatus: *damage*, *overdue loans* (open loans past their due date, most overdue first, with the person, the pieces still out and *N of M open loans overdue*) and *maintenance & calibration* (tasks overdue or due within 14 days, plus how many tasks are open and how many were completed in the range). The PDF report appends the same views as tables.

## Spreadsheet exports (REPORT-05)

Next to *Share PDF report* the report page offers *Activity CSV* — every entry of the selected shelf inside the selected range, oldest first, with date, time, item, formula or category, action, amount, unit, note, entry id and the UTC timestamp — and *Inventory CSV*, the whole shelf with every detail column (supplier, CAS, concentration, location, expiry, hazards, barcode, QR code for chemicals; serial, condition, assigned to, location, purchase and warranty dates, barcode for apparatus) plus the stock state. Files are written by one shared writer: RFC 4180 quoting, CRLF line endings and a UTF-8 byte-order mark so Excel opens them correctly, numbers left bare so they stay numbers, and any cell that starts with `=`, `+`, `-`, `@`, a tab or a carriage return is prefixed with an apostrophe so a note like `=HYPERLINK(...)` is shown as text rather than run. The Settings backup export uses the same writer and the CSV importer removes the apostrophe again, so round trips are lossless.

## Branded PDF reports (REPORT-06)

Settings gains a *report branding* card: lab or institution name, a contact line, an address and an optional logo (PNG or JPEG up to 2 MB, copied into the app's private folder). Everything stays on the device and is never uploaded; leave it empty and reports simply say *Lab Wizard*. *Share PDF report* now produces a clean A4 layout: the branding, report title and range repeat in the header of every page; summary cards show counts, per-unit quantities and the change against the previous period; then the stock-health line, the activity table (oldest first), run-out estimates with the numbers behind them, and the expiry, damage, overdue-loan and maintenance views; the footer carries *Page x of y* and when the report was generated.

## Password recovery (ACCOUNT-01)

*Forgot password?* on the sign-in card sends the Supabase recovery email with the redirect `com.labwizard.labwizard://reset-password`. **One-time setup in the Supabase dashboard:** Authentication → URL configuration → *Redirect URLs* → add `com.labwizard.labwizard://reset-password` (the web app's Site URL stays as it is). Android registers that scheme in `AndroidManifest.xml`, so tapping the link on the phone opens Lab Wizard; supabase_flutter exchanges the link for a session and the app shows *choose a new password* (with a confirmation field and *Not now, keep my password*). Because the app uses the PKCE flow, the link must be opened on the same phone that requested it; an expired or reused link is explained inline. The confirmation message is the same whether or not the address has an account, and Supabase's send-rate limit surfaces as *Too many attempts. Wait a minute and try again.*

## Change password (ACCOUNT-02)

Settings → *your account* → **Change password** asks for the current password, the new one (at least six characters and different from the current) and a confirmation. The current password is verified with a fresh sign-in before anything changes, so a phone left unlocked cannot quietly take the account over; a wrong entry reads *The current password is not right.*, and other server errors stay in the sheet. Tick *Also sign out my other devices* to revoke every other session once the new password is saved — this phone stays signed in.

## Export and account deletion (ACCOUNT-03)

Run `supabase/009_account_deletion.sql` once: it adds `public.delete_my_account()`, a SECURITY DEFINER function that only `authenticated` users can call and that only ever acts on the caller (`auth.uid()`): it deletes their rows in every Lab Wizard table, the sync tombstones, and finally the `auth.users` row. Nothing existing changes. In the app, Settings → *danger zone* → **Delete account…** shows what will disappear (counts of chemicals, apparatus, log entries, open loans and tasks) with **Export my data first**, which shares four CSV files (chemicals, apparatus, chemical activity, apparatus activity — same formula-safe format as the report exports). The second step requires typing `DELETE` and the current password, which is verified with a fresh sign-in before the function is called. Afterwards the offline copy on the phone is wiped and the sign-in card shows *Your account and all its data were deleted.* Retention is simple: Lab Wizard keeps no copy; only Supabase's routine backups age out on the project's own schedule. Deletion needs a connection and is refused offline; if the function has not been installed yet, the app says so and names the script.

## Sessions and devices (ACCOUNT-04)

Supabase Auth does not let apps list a user's individual devices, so Lab Wizard does not pretend to: the *sessions & devices* card in Settings describes this phone's session (signed in when, account since, sign-in method, whether the email is confirmed) and says so. What Supabase does support is scoped sign-out, so the card offers **Sign out other devices** (every other phone, tablet and browser must sign in again; this phone stays in) and **Sign out everywhere** (all sessions end, including this one, and the offline copy is removed), each behind a confirmation. The button on the account card is explicitly *Sign out (this phone)* and ends only this device's session.

## App lock (SECURITY-01)

Settings → *app lock* can require a 4–8 digit PIN whenever Lab Wizard is opened on this phone. The PIN never leaves the device: it is stored only as a salted PBKDF2-HMAC-SHA256 hash in the platform secure storage (Android Keystore-backed `flutter_secure_storage`), keyed per account, so two accounts on one phone keep separate PINs and an ordinary sign-out keeps the lock for the next sign-in. When the phone has a screen lock or biometrics, the lock screen also offers fingerprint / face / phone screen lock through `local_auth`; the keypad is always the fallback. *Lock again* chooses how long the app may stay in the background before it locks (immediately, 1, 5 or 15 minutes; a cold start is always locked), *Lock now* locks straight away, and changing or turning off the PIN requires the current one. Five wrong PINs start a 30 s cool-down that doubles up to 10 minutes and survives restarts. *Forgot PIN?* on the lock screen signs this phone out — the account password is needed to get back in, nothing in the account changes.

What the lock does **not** do, stated in the card as well: it only hides the app's screens on this phone. The offline SQLite copy and the rows in Supabase are not encrypted by it, and the Android app switcher may still show the last screen. Android specifics: `MainActivity` extends `FlutterFragmentActivity`, the manifest declares `USE_BIOMETRIC`, and the launch/normal themes have AppCompat parents (all required by `local_auth`).

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

## TalkBack (A11Y-01)

Every shelf row or card is **one spoken item**: name, amount, stock status in words, formula or category, and whatever is otherwise only an icon or a colour (expired / expires soon, hazards, condition, assignee, loans, due services, selection state). *Use* / *Report damage* and *Restock* are offered in TalkBack's actions menu (swipe up or down, or the local context menu) instead of the swipe gestures; double-tap opens the details and long-press starts selection. Page titles are headings, so heading navigation works; the dashboard tiles read as "3, low stock, button"; the activity charts speak a summary (total, busiest day, quiet days) instead of bars; the scanner's status line is a live region, so "Found Acetone" or "not in your lab notebook" is announced as soon as a code is read; stock status is spoken as "in stock / low stock / out of stock" without symbols. Icon-only buttons all have tooltips (which TalkBack reads as labels). An automated audit (`test/a11y_semantics_test.dart`) checks that every tappable node on the shelves has a label and that the row summaries, custom actions, heading flags and A–Z strip states are present.

## Large text (A11Y-02)

The app follows the system font size up to Android's maximum (200 %); anything larger (developer settings, some launchers) is capped there so verified layouts stay valid. Everything is laid out with wrapping or flexible widgets: shelf quantities shrink to fit, dashboard tiles and the week chart grow with the font, report metric tiles stack under large text or on narrow screens, the "more details" headers wrap, and sheets scroll. Two pieces of chrome deliberately clamp their own text: the bottom navigation labels (130 %, the icons carry the meaning) and the A–Z strip letters (sized by their slot; TalkBack has the labels). `test/large_text_test.dart` pumps the shelves, item/edit/consume sheets, dashboard, reports, sync center, lock screen and navigation at 200 % on a 360 × 740 phone and fails on any overflow.

## Small phones, landscape and tablets (A11Y-03)

Layouts are built from wrapping and flexible widgets, so a 320 px phone gets the same screens as a 6-inch one. From 720 px of width (tablets, large phones in landscape) the shelves show two items per row in both densities; the dashboard puts its four tiles in one row from 600 px; bottom sheets stay at most 640 px wide and scroll; the A–Z strip shows every second or third letter when the list area is short (phone landscape) and disappears when there is no room, with the collapsing heading (UX-03) giving the list back most of a landscape screen. `test/responsive_layout_test.dart` renders the shelves (both densities, selection, long lists with the strip), dashboard, reports, detail sheet and add form at 320 × 568, 740 × 360, 600 × 960 and 1024 × 720 and fails on any overflow, and checks the two-column shelf, the one-row dashboard and the thinned strip.

## Contrast and colour vision (A11Y-04)

No state is carried by colour alone: stock status is always written next to its colour (badge, compact-row word, margin note), the stock bar changes its hatch pattern with the state (sparse stripes in stock, dense stripes when low, cross-hatch when empty, a ghost cross-hatch on an empty track), expiry and hazards have icons and words, apparatus condition and loans are icon + text, and sync states are words. The status colours were darkened so that they pass WCAG AA (4.5:1) as text on paper and card: amber 5.2:1, green 5.5:1, red 5.6:1 in the light theme; the dark theme's red was lifted to 5.1:1 on the dark card. `test/a11y_semantics_test.dart` checks every text colour of both palettes against paper and card (and white on the status fills) with the WCAG formula; the screenshot-based `textContrastGuideline` proved unreliable with the paper texture.

## Touch targets and motion (A11Y-05)

Every control on the shelves, dashboard, reports and sync center is at least 48 × 48 dp: the hand-written filter words, sort control, card actions and "more details" headers got invisible padding, the compact-row buttons dropped their compact density, and the A–Z strip — whose letters cannot be 48 dp — is one control for assistive technology with a *Jump to …* action per available letter. Motion follows the system's *Remove animations* setting: card stagger, count-ups, stock bars, the heading underline, the week chart, navigation and selection transitions, dialog/sheet size changes and the scanner's sweeping line all complete immediately (the scanner line does not even tick), and nothing conveys information only through movement. `test/a11y_touch_motion_test.dart` runs Flutter's `androidTapTargetGuideline` over those screens and checks that the dashboard and shelf have no running animations two frames after they appear with animations disabled.

## Crash reports (OBS-01)

Off by default. Settings → *crash reports* turns on a local, opt-in log of errors the app runs into: the message, the stack trace, the screen it happened on, the app build and the Android version — nothing else. Before a report is stored it is scrubbed: every item name, note, supplier, location, person, code and the account e-mail known on the phone are replaced with `[redacted]`, and e-mail addresses, bearer tokens, URL query values and long digit runs are removed by pattern. Reports live only on the phone (SharedPreferences), are deleted after 14 days, and only the newest 30 are kept; *Share reports* hands the JSON to the system share sheet, *Delete all* removes them. Nothing is uploaded: a hosted crash service has not been chosen, and when one is, the same scrubbing and retention rules apply and the switch stays opt-in. The CI build stamps `APP_BUILD` so reports carry the build name.

## Automated quality gates (TEST-01 … TEST-06)

**Golden screenshots.** `test/golden/screens_golden_test.dart` renders the chemical shelf (detailed, compact, empty), the apparatus shelf, an item detail sheet, the sync center with conflicts and the lock screen in light and dark, and compares them with the PNGs in `test/golden/goldens/`. The fixtures use fixed dates so a picture never depends on the day it is taken; the app's handwriting fonts are loaded for every test by `test/flutter_test_config.dart`. Font rendering differs between operating systems, so the comparisons run on Linux only (CI) and the images are produced there: after an intentional visual change, request a re-render by editing `test/golden/UPDATE_GOLDENS` (a date and a reason) and pushing — the **Update golden screenshots** workflow renders on Linux and commits the new images (the *Run workflow* button works too once GitHub has seen the workflow run); the regular run then compares against them. An unintentional change fails CI with a diff image in the test output.

**Offline outbox integration.** `test/outbox_integration_test.dart` drives `InventoryRepository` against an in-memory PostgREST (`test/support/fake_postgrest.dart`, shared with the conflict tests) through the paths that matter offline: add, update and action queued without a connection and flushed in order; a server error that marks one change failed while the others go through, and *retry* sending it; an action whose reply was lost being replayed with the same operation id and applied once (the fake mirrors the real `apply_inventory_action` idempotency); and per-user isolation of queues and offline copies, including a sign-out wipe of one account. Conflict paths are covered by `sync_conflicts_test.dart`, paging and tombstones by `incremental_sync_test.dart`.

**Responsive and font matrix.** `test/responsive_font_matrix_test.dart` renders the shelf (both densities), the dashboard and an item sheet at 320 × 568, 740 × 360, 600 × 960 and 1024 × 720, each at 130 % and 200 % text; together with `responsive_layout_test.dart` and `large_text_test.dart` this is the overflow gate for small widths, tablets, landscape and large text.

**Scanner and QR.** `test/scanner_qr_test.dart` pins the routing rules (prefixed and bare chemical codes, apparatus payloads that never fall back to chemicals, linked barcodes that match only exactly and only when linked), feeds malformed codes (empty, truncated prefixes, wrong case, control characters, emoji, 100 000-character strings) through the resolver, checks that every printed label scans back to its own item, runs a 300-scan batch with exact counts, and inspects the generated PDF bytes (header, trailer, A4 media box, page objects per layout). Batch UI, scan actions and barcode linking have their own tests.

**Large data.** `test/large_data_test.dart` builds a shelf of 1 000 chemicals in both densities and checks that it stays lazy (fewer than 60 rows exist at any time, before and after flinging), that a search narrows to one row, a filter re-runs over everything and an A–Z jump lands, each within loose budgets, and that bucketing, trends and run-out estimates over 20 000 log entries finish within budget.

**Navigation paint regression.** `test/navigation_paint_test.dart` mounts the home shell and checks that inactive tabs stay mounted (state survives) but never paint (their `RepaintBoundary` has no layer), cannot be hit, are absent from the semantics tree and have muted tickers — and that switching tabs flips all of that.

## Multi-Lab & Organizations (ORG-01 … ORG-05)

Run `supabase/010_multi_lab_organizations.sql` to add collaborative multi-lab support. It creates `organizations`, `labs`, `organization_members`, and `lab_members` tables, plus nullable `organization_id` and `lab_id` columns on `chemicals`, `apparatus`, and `consumption_logs`. Dual permissive RLS policies ensure existing single-user personal rows remain accessible via `user_id = auth.uid()` so the Next.js web app works without modification, while team members can collaborate in shared labs with role-based permissions (manager, researcher, viewer).

In the mobile app:
- A notebook header chip lets users switch between their **Personal Lab** and shared team labs via `showLabSwitcherSheet`.
- Active lab selection persists in SharedPreferences per signed-in user.
- Local SQLite database (schema version 5) scopes offline cached records by `lab_id`, ensuring team inventory and personal inventory remain strictly isolated.
- Settings includes an **organization & labs** card displaying workspace status, user role, and lab switching shortcuts.

## Signing and Google Play Distribution (RELEASE-01, RELEASE-02)

The Gradle configuration (`android/app/build.gradle.kts`) and GitHub Actions workflows feature **dual-mode signing**:

1. **Development Mode (Default)**: Uses `android/app/lab-wizard-github.jks`, a stable development key committed intentionally so phone testers can install and update APKs directly from GitHub Releases without configuring secrets.
2. **Production Mode (Private)**: When private credentials (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) are added to GitHub Secrets (or locally in `key.properties`), the build automatically signs with the private keystore and produces both the universal APK and the Google Play Android App Bundle (`.aab`).

For complete instructions on keystore generation, key rotation/recovery, Google Play App Signing, and the Play Console Data Safety questionnaire, consult [`docs/RELEASE_AND_PLAY_STORE_GUIDE.md`](../docs/RELEASE_AND_PLAY_STORE_GUIDE.md).
