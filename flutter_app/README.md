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

## Sync center (SYNC-01)

Settings → *Sync center* (also reachable from the dashboard sync banner) lists every change waiting on the device with its attempts, last error and status. Connection problems keep a change `pending` and retry automatically; any other server error marks only that change as `failed` so other items keep syncing. Failed changes can be retried individually, all at once, or discarded — discarding rolls the offline copy back to what it was before the change.

## Signing

GitHub builds use `android/app/lab-wizard-github.jks`, a stable development-distribution key committed intentionally so phone-only testers can install future APKs as updates. Do not use this key for Play Store production. Configure private Play App Signing before publishing commercially.
