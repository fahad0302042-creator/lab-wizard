# Lab Wizard Flutter Improvement Roadmap

This is the authoritative checklist for the post-1.0.4 Android improvement program. Items are implemented in ID order unless a prerequisite requires otherwise. An item is only marked complete after source validation, automated tests, a successful signed GitHub APK build, and phone verification where applicable.

Status legend: `TODO`, `IN PROGRESS`, `BLOCKED`, `VALIDATING`, `RELEASED`.

Ground rules for every item:

- The Next.js web app in `src/` and the Supabase schema it relies on are never broken. Database changes are additive only (new nullable/defaulted columns, new tables, new RPCs, new indexes) and live in numbered files under `flutter_app/supabase/`.
- The Flutter app keeps working against the current schema when an optional migration has not been applied yet.
- Verification runs on GitHub, not on developer machines: `.github/workflows/flutter-branch-ci.yml` formats, auto-fixes, analyzes, tests, and builds a signed APK artifact for every branch push; `android-apk.yml` publishes releases from `main`.

## Milestone A — Large-inventory speed and daily usability

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| UX-01 | VALIDATING | Compact/detailed inventory mode | User can switch modes from either shelf; preference persists; compact rows retain quantity, status, details, use/damage and restock access. | None |
| UX-02 | VALIDATING | Alphabetical quick navigation | A–Z control jumps to the first matching item; unavailable letters are visibly disabled; works after sorting/searching. | UX-01 |
| UX-03 | VALIDATING | Sticky search and filters | Collapsing shelf heading; search/filter/sort controls remain reachable while scrolling without hiding most of the list. | UX-01, UX-02 |
| UX-04 | VALIDATING | Undo inventory actions | Recent consume/restock/damage can be reversed safely; reversal is represented in the audit trail and works with offline outbox retries. | SYNC-01 |
| BATCH-01 | VALIDATING | Batch restock | Multi-select chemicals/apparatus, validate amounts, show progress and record separate audit entries. | None |
| BATCH-02 | VALIDATING | Batch threshold update | Multi-select items and set low-stock values with preview and validation. | None |
| BATCH-03 | VALIDATING | Batch category/location assignment | Apply supported shared fields to selected items; incompatible fields are not silently changed. | DATA-01 |
| BATCH-04 | VALIDATING | Safe multi-delete | Selection summary, typed confirmation for large deletions, online requirement and clear audit/export warning. | None |
| QR-01 | VALIDATING | Selected-item QR printing | Select specific chemicals/apparatus and print only those labels; retain 40-per-A4 option. | None |

## Milestone B — Import and higher-quality data entry

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| IMPORT-01 | VALIDATING | Android CSV import | File selection, column mapping, preview, validation, duplicate warnings, partial-error report and confirmed import. | DUP-01 |
| DUP-01 | VALIDATING | Duplicate detection | Normalized name/formula/category checks; view existing or explicitly add anyway. | None |
| FORM-01 | VALIDATING | Remember form preferences | Persist recent unit, category, action amount and preferred threshold behavior per user/device. | None |
| DATA-01 | VALIDATING | Additive chemical metadata | Optional supplier, CAS, concentration, location, expiry and hazard fields; old web/app rows remain valid. | Additive SQL migration |
| DATA-02 | VALIDATING | Expiry and hazard presentation | Shelf/detail indicators, filters and report support without overwhelming normal cards. | DATA-01 |

## Milestone C — Apparatus operations

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| GEAR-01 | VALIDATING | Serialized apparatus metadata | Serial number, condition, assigned person, purchase date and warranty expiry. | Additive SQL migration |
| GEAR-02 | VALIDATING | Checkout and return | Clear availability, borrower, due date, return condition and immutable history. | GEAR-01 |
| GEAR-03 | VALIDATING | Maintenance and calibration | Due dates, completion records, notes and status warnings. | GEAR-01 |
| GEAR-04 | VALIDATING | Apparatus history | Unified checkout, return, damage, maintenance and calibration timeline/report. | GEAR-02, GEAR-03 |

## Milestone D — Notifications

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| NOTIFY-01 | VALIDATING | Notification preferences | Per-type controls, permission education and Settings management. Settings → *notifications*: master switch asks for the Android 13+ permission, blocked state explained with an *open system settings* button, per-topic switches, warning windows, reminder hour and a test notification; stored on the device only. | None |
| NOTIFY-02 | VALIDATING | Low-stock and expiry alerts | Deduplicated local alerts with sensible timing and direct item navigation. Alerts fire once per day per item (persisted), more than three at once collapse into one digest, expiry reminders are scheduled ahead (N days before + expiry day) so they arrive with the app closed, and tapping opens the item sheet. | DATA-01, NOTIFY-01 |
| NOTIFY-03 | VALIDATING | Return/calibration alerts | Overdue checkout, maintenance and calibration notifications. Loan due-time reminders, overdue-return alerts, service *due soon* / *due today* / *overdue* alerts; all open the apparatus sheet. | GEAR-02, GEAR-03, NOTIFY-01 |
| NOTIFY-04 | VALIDATING | Sync and weekly summary alerts | Stale outbox warning and optional weekly stock summary. Failed outbox changes raise one alert that opens the sync center; the optional weekly summary repeats on a chosen weekday/hour and the *needs attention* screen shows the same digest text in the app. | SYNC-01, NOTIFY-01 |

## Milestone E — Offline and synchronization reliability

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| SYNC-01 | VALIDATING | Sync center | List pending/failed operations, attempts, error, retry one/all, safely discard where allowed, and last successful sync. | Local DB migration |
| SYNC-02 | VALIDATING | Incremental synchronization | `updated_at` cursor, pagination, tombstone/deletion handling, full-resync escape hatch and per-user isolation. Migration 007 (additive: `updated_at` + triggers + `deleted_rows`); keyset paging on `(updated_at, id)` in pages of 500 with a 2-minute overlap; tombstones applied per table; automatic full download when cursors are missing or older than 120 days; **Download everything again** in the sync center; per-user cursors and a defensive `user_id` filter; paged full downloads on servers without the migration. | Additive SQL migration |
| SYNC-03 | VALIDATING | Background synchronization | Connectivity/app-resume triggers and Android background scheduling without duplicate actions or battery abuse. Foreground: sync on app resume (skipped when a download happened < 2 min ago and nothing is queued) and when the connection returns. Background (WorkManager): a periodic job every 1/3/6/12/24 h (user setting, default hourly, optional Wi-Fi only, battery-not-low) that sends the outbox and downloads changes, plus a one-off *flush* job scheduled when the app is left with queued changes (runs when a network is available, exponential retry). No duplicate actions: a job that fires while the app process is alive hands the work to the main isolate over `IsolateNameServer` (single Supabase session, so refresh-token rotation cannot sign the user out); only when nobody answers does the job start its own client from the persisted session. The outbox itself is idempotent (`operation_id`). Settings card (toggle, frequency, Wi-Fi only, last run + result) and a sync-center card; jobs are cancelled on sign-out. | SYNC-01, SYNC-02 |
| SYNC-04 | VALIDATING | Conflict resolution | Explain server/local conflicts and offer safe resolution; never silently overwrite unrelated newer data. Edits send only the fields that actually changed and are applied as a compare-and-set (PostgREST filters on the last-seen values, no server change): unrelated newer server data is never touched, and a field changed on both sides becomes a *conflict* — live in the edit form (dialog: keep server values / overwrite with mine / cancel) or, for a queued change, in the sync center (badge, plain-language explanation with both values, *keep server values*, *overwrite with mine*, *discard*). Stock conflicts (server has less than a queued consume/damage needs, or an undo the server cannot honour) explain the amounts and offer *apply what is left* where that makes sense; a deleted item is explained and can only be removed. Conflicts are never retried blindly (*retry all* skips them) and survive restarts (local DB v4 adds an outbox `conflict` column). Servers without the atomic RPC get the same protection: quantity writes are rebased on the server's value instead of overwriting it. | SYNC-02 |

## Milestone F — Scanner and QR workflow

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| QR-02 | VALIDATING | Bulk apparatus QR labels | A4 output and selected-item support using stable apparatus identifiers. Apparatus labels encode the row id (`labwizard:apparatus:<id>`, unchanged by renames) and print the name, category, serial number and a short id for eye-matching; the apparatus shelf gets *QR labels for all* in the menu and *labels* in the selection bar, sharing one A4 sheet builder with chemicals (grid choice 40 / 24 / 12 per page, page count preview, print or share the PDF). | QR-01 |
| QR-03 | VALIDATING | Save/share individual label | Export a clean label image/PDF from item details. The item sheet shows the label as it will be exported (QR left, name/details right) with *share image* (PNG through the system share sheet, so it can be saved, messaged or printed), *PDF* (single 80 × 50 mm page) and *print*. | None |
| SCAN-01 | VALIDATING | Recent scans | Device-local, user-scoped list with direct item access and clear-history control. The scanner page keeps the last 30 codes per signed-in user in shared preferences (`scans.<user id>`, never uploaded): matched items open their sheet with one tap, items deleted since are marked *removed*, unknown codes are kept as *not matched* with a copyable payload, and *clear* asks before forgetting the list. Scan matching moved into a pure `resolveScan` function. | None |
| SCAN-02 | VALIDATING | Continuous batch scanning | Scan multiple labels without reopening camera; duplicate handling and completion summary. A *Single / Batch* switch under the camera: in batch mode every recognised label is added to a `ScanBatch` while the camera keeps running, a repeated label increments its count (with a lighter haptic and an *already in batch ×n* message) instead of appearing twice, the same code re-read within two seconds is ignored, unknown codes are kept for the summary, and *Finish (n)* opens a summary sheet (items with counts, unknown codes, open item, *Keep scanning* or *Done*). | SCAN-01 |
| SCAN-03 | TODO | Scan-and-act | After recognition, enter quick amount and perform consume/restock/return without unnecessary navigation. | GEAR-02 for returns |
| SCAN-04 | TODO | External barcode support | Optional EAN/Code formats, explicit item association and no unsafe automatic matching. | DATA-01 |

## Milestone G — Reports and exports

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| REPORT-01 | TODO | Flexible date ranges | 7-day, 30-day, monthly and custom inclusive ranges with correct local-day handling. | None |
| REPORT-02 | TODO | Usage/restock trends | Separate action counts and unit-aware quantities; comparison with previous period. | REPORT-01 |
| REPORT-03 | TODO | Run-out estimates | Explainable estimate based on adequate history; no estimate when data is insufficient. | REPORT-01 |
| REPORT-04 | TODO | Expiry and apparatus reports | Expiry, damage, overdue checkout, maintenance and calibration views. | DATA-01, GEAR-04 |
| REPORT-05 | TODO | CSV/Excel-friendly exports | Formula-injection-safe inventory and log exports with selected date range. | REPORT-01 |
| REPORT-06 | TODO | Branded PDFs | Optional lab name/logo/contact fields and clean print layout. | Future organization settings or local profile |

## Milestone H — Account, security and distribution

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| ACCOUNT-01 | TODO | Complete password recovery | Supabase allowlisted redirect, Android deep link, recovery screen and successful password update test. | Supabase Auth URL configuration |
| ACCOUNT-02 | TODO | Change password | Authenticated re-entry/validation and clear success/error states. | None |
| ACCOUNT-03 | TODO | Data export and account deletion | Export first, explicit destructive confirmation, server-side deletion path and clear retention behavior. | Secure server function |
| ACCOUNT-04 | TODO | Active sessions/devices | Display sessions where supported and provide sign-out-all control. | Supabase/API capability review |
| SECURITY-01 | TODO | Optional biometric/PIN app lock | Local secure storage, fallback behavior and no false claim of server-side encryption. | Secure storage dependency |
| RELEASE-01 | BLOCKED | Private production signing | Private key in GitHub Secrets, no key in repository, documented recovery process and signed verification. | Owner-created private key/secret access |
| RELEASE-02 | BLOCKED | Google Play distribution | Production package/signing strategy, Play App Signing, privacy/data-safety listing and tested upgrade path. | RELEASE-01, Play Console access |

## Milestone I — Accessibility, device quality and observability

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| A11Y-01 | TODO | TalkBack audit | Meaningful labels/order for custom controls, charts, scanner, stock status and actions. | None |
| A11Y-02 | TODO | Large-text support | No clipping at Android maximum practical font scale; scroll/flexible layouts where required. | None |
| A11Y-03 | TODO | Small phone/landscape/tablet layouts | Tested widths, responsive density and no overlaps across supported orientations. | UX-01, UX-03 |
| A11Y-04 | TODO | Contrast/color-blind support | Status never depends only on color; contrast audit; patterns and labels remain available. | None |
| A11Y-05 | TODO | Touch and reduced-motion audit | Minimum targets, predictable focus, no essential animation and all motion respects preference. | None |
| OBS-01 | TODO | Privacy-aware crash diagnostics | Opt-in/transparent collection, scrub sensitive inventory values and document retention. | Service selection/privacy review |

## Milestone J — Automated quality gates

| ID | Status | Improvement | Acceptance criteria | Dependencies |
|---|---|---|---|---|
| TEST-01 | TODO | Golden screenshot tests | Main screens, light/dark, compact/detailed and representative empty/loaded states. | UX-01 |
| TEST-02 | TODO | Navigation paint regression | Automated assertion that inactive tabs are offstage and cannot paint or receive input. | None |
| TEST-03 | TODO | Responsive/font tests | Small width, tablet, landscape and large text overflow checks. | A11Y-02, A11Y-03 |
| TEST-04 | TODO | Offline/outbox integration tests | Add/update/action/retry/idempotency/conflict paths and per-user isolation. | SYNC-01, SYNC-02 |
| TEST-05 | TODO | Scanner and QR tests | QR routing, malformed codes, apparatus labels, batch scanning and generated PDF structure. | QR-02, SCAN-02 |
| TEST-06 | TODO | Large-data performance tests | 500–1,000 items, search/sort/filter/scroll and report responsiveness with budgets. | UX-01, SYNC-02 |

## Future platform milestone — Multi-lab and multi-organization

This remains intentionally after the current single-lab quality program: organizations, memberships, lab types, roles, tenant RLS, organization/lab-scoped offline cache, quotas, invitations and optional dedicated enterprise projects.

## Status log

| Date | Item | Change | Notes |
|---|---|---|---|
| 2026-09-21 | UX-01, UX-02 | `VALIDATING` → `IN PROGRESS` | Audit of `main` (700020e) found neither feature in `flutter_app/lib`; both are implemented as part of this program. |
| 2026-09-21 | CI | Added `flutter-branch-ci.yml` | Branch pushes are formatted, auto-fixed, analyzed, tested and built on GitHub; APK artifacts are kept for 7 days for phone verification. Android `versionCode` is now minutes-since-epoch in both workflows so branch builds and releases install over each other as updates. |
| 2026-09-21 | UX-01, UX-02, UX-03 | `IN PROGRESS` → `VALIDATING` | Compact/detailed shelf mode, A–Z quick navigation and collapsing heading with sticky controls implemented with widget tests; awaiting green branch CI + phone check of the branch APK. |
| 2026-09-21 | SYNC-01 | `TODO` → `VALIDATING` | Local DB v2 (outbox status/label/last attempt + `sync_meta`), per-change failure handling (connectivity keeps `pending`; other errors mark `failed` and do not block other items), sync center screen with retry one/all + safe discard, last-successful-sync shown in Settings/Dashboard. SQLite-backed tests run on CI. Pulled ahead of UX-04 because UX-04 depends on it. |
| 2026-09-21 | UX-04 | `TODO` → `VALIDATING` | Undo from the post-action snackbar and from item history (entries ≤ 7 days). Mirrors the web app's undo (restore quantity, delete entry) plus an additive `inventory_reversals` table + idempotent `undo_inventory_action` RPC (`flutter_app/supabase/002_undo_inventory_action.sql`) so the history shows "undone" entries; web-parity fallback when the migration is absent. Queued-but-unsynced actions are cancelled; offline undos are queued as `undo_action` and can be discarded from the sync center with a full local rollback. |
| 2026-09-21 | BATCH-01, BATCH-02, BATCH-04, QR-01 | `TODO` → `VALIDATING` | Shared multi-select mode on both shelves (long-press or overflow "select items…", select/clear shown, back leaves selection). Bottom bar: batch restock (per-item amounts, same-amount fill, validation, progress, one audit entry per item, retry failed rows), batch threshold (old → new preview, unchanged items skipped), QR labels for the selected chemicals (same 40-per-A4 sheet), safe delete (summary with history counts, export warning, unsynced items blocked, offline blocked, typed `DELETE` for 5+ items, per-item failure report). BATCH-03 stays TODO until DATA-01. |
| 2026-09-21 | DUP-01, FORM-01 | `TODO` → `VALIDATING` | Add sheet compares normalized name/formula (chemicals) and name/category (apparatus) with the shelf, shows matches inline with *view* / *add anyway*, and blocks saving until acknowledged. Unit, category, low-stock level and action amounts are remembered per user + device (SharedPreferences) and prefilled; both prefills are switchable and forgettable in Settings. Widget + unit tests added. |
| 2026-09-21 | DATA-01, DATA-02 | `TODO` → `VALIDATING` | Additive `flutter_app/supabase/003_chemical_metadata.sql` (nullable `supplier`, `cas_number`, `concentration`, `location`, `expiry_date`, `hazard_classes` + partial index). Model, cache, search and CSV export carry the fields; add/edit sheets get a collapsible *more details* section (CAS check digit, GHS chips, YYYY-MM-DD or date picker). Expired / ≤ 30-day chemicals show a badge on cards and compact rows and an *expiring* shelf filter; the item sheet shows the details, expiry copy and hazard chips. Metadata is only sent when changed and a missing column produces a migration hint instead of a raw error. |
| 2026-09-21 | BATCH-03 | `TODO` → `VALIDATING` | Selection bar gains *location* (chemicals) / *category* (apparatus) with an old → new preview, one-tap suggestions from existing locations and unchanged rows skipped. The field is bound to the shelf so incompatible fields can never be written. Needs migration 003 for chemicals; a missing column is reported per row instead of failing silently. |
| 2026-09-21 | IMPORT-01 | `TODO` → `VALIDATING` | `file_selector`-based CSV import from Settings: RFC 4180 parser (quotes, CRLF, BOM, `;`/tab sniffing), header auto-mapping with manual dropdowns, shelf selector or `type` column, per-row validation (errors vs warnings), duplicate detection against the shelf and within the file (skip by default, opt-in import), sequential import with progress, and a report of every skipped/failed line that can be shared. Unit + widget tests cover parser, mapping, validation and the screen flow. |
| 2026-09-21 | GEAR-01 | `TODO` → `VALIDATING` | Additive `flutter_app/supabase/004_apparatus_metadata.sql` (nullable `serial_number`, `condition`, `assigned_to`, `location`, `purchase_date`, `warranty_until` + partial index). Model/cache/search/CSV export/import carry the fields; add/edit sheets get a collapsible *more details* section (condition dropdown, date entry/picker with strict YYYY-MM-DD validation); item sheet shows details with warranty copy; shelf rows mark needs-repair/fair/retired condition, assignee and warranty ending. Metadata only sent when changed; missing column → migration hint. |
| 2026-09-21 | GEAR-02 | `TODO` → `VALIDATING` | Additive `flutter_app/supabase/005_apparatus_checkouts.sql` (`apparatus_checkouts` table, RLS own rows, cascade from `apparatus`, unique `(user_id, operation_id)`). One row per loan with `quantity`/`returned_quantity`; partial returns raise the returned count and the loan closes when everything is back. Item sheet: availability line, *Check out* (person with recent-name chips, whole pieces ≤ available, optional due date, note), open loans with due/overdue copy and per-loan *return*, recent returns. Shelf rows mark *N out* / *overdue*. Stock counts are never changed by a loan. Offline: `checkout_apparatus` / `return_apparatus` outbox entries, discard restores the previous state and drops dependent returns. SQLite + widget tests added. |
| 2026-09-21 | GEAR-03 | `TODO` → `VALIDATING` | Additive `flutter_app/supabase/006_apparatus_maintenance.sql` (`apparatus_services`: kind maintenance/calibration, title, note, `due_at`, `completed_at`, `performed_by`, `result`; RLS own rows, cascade, unique `(user_id, operation_id)`). Item sheet section with *Schedule* (kind toggle, title, due date + interval chips, note), open tasks soonest first with due/overdue copy and *done*, completed history. Completion sheet records date (not in the future), performer with recent-name chips, result chips, note and an optional next task of the same kind. Shelf rows mark *calibration overdue* / *maintenance due* (≤ 14 days). Offline `schedule_service` / `complete_service` outbox entries with discard rollback (a discarded schedule also drops its queued completion). SQLite + widget tests added. |
| 2026-09-21 | GEAR-04 | `TODO` → `VALIDATING` | Pure `buildApparatusHistory` merges logs, undo reversals, checkouts/returns (late flag) and scheduled/completed tasks into one newest-first timeline; item sheet history shows the mix (latest 8) plus *Full history & report*; new `ApparatusHistoryScreen` with summary card, kind filters and a shareable plain-text report (no CSV, so no formula injection). No database change. Unit + widget tests added. |
| 2026-09-21 | NOTIFY-01, NOTIFY-02, NOTIFY-03, NOTIFY-04 | `TODO` → `VALIDATING` | `flutter_local_notifications` + `timezone`: preferences card (master switch with permission education, per-topic switches, reminder hour, weekly summary weekday), local low-stock/expiry alerts deduplicated per item per day, overdue checkout / maintenance / calibration reminders scheduled ahead, failed-outbox alert opening the sync center, optional weekly summary, and an in-app *needs attention* screen with the same content. |
| 2026-09-21 | SYNC-02 | `TODO` → `VALIDATING` | Additive migration 007 (`updated_at` + touch triggers, `deleted_rows` tombstones); per-user `(updated_at, id)` cursors in `sync_meta` (local DB v3), keyset paging of 500 with a 2-minute overlap, tombstone application, automatic full download when cursors are missing/old, **Download everything again**, legacy fallback with a hint when the server lacks the migration. |
| 2026-09-21 | SYNC-03 | `TODO` → `VALIDATING` | `workmanager` periodic job (1–24 h, Wi-Fi-only option, battery-not-low) + one-off outbox flush when the app is backgrounded with queued changes; resume/connectivity foreground triggers; main-isolate delegation over `IsolateNameServer` so the persisted Supabase session is only ever used by one live isolate; standalone background client only when the app process is gone. Settings + sync-center cards show the last run; tests cover preferences, bookkeeping, scheduling, triggers and the isolate bridge. No database change. |
| 2026-09-21 | SYNC-04 | `TODO` → `VALIDATING` | Field-level compare-and-set updates (only changed fields, guarded by their last-seen values through PostgREST filters; array fields checked against a fresh copy), `SyncConflict` model (changed / deleted / stock) persisted in the outbox (local DB v4, additive column), conflict card in the sync center with explanations and kind-specific decisions, edit-form dialog for live conflicts, RPC error mapping (insufficient stock, item not found, undo refused), *apply what is left* for stale consume/damage entries, and rebased quantity writes on the legacy (no-RPC) path. Fake-PostgREST repository tests, SQLite migration tests and widget tests added. No database change. |
| 2026-09-21 | QR-02, QR-03 | `TODO` → `VALIDATING` | Shared label module (`lib/features/labels`): `LabelSpec` (chemical = web-compatible `qr_code` payload, apparatus = stable row id + short id), A4 sheet builder with 40/24/12-per-page grids and a print-or-share dialog, single-label 80 × 50 mm PDF, PNG renderer with on-screen preview; apparatus shelf menu + selection bar get labels; item sheet gets share image / PDF / print. Unit tests for payloads, page counts and generated PDFs, widget tests for the dialog, the apparatus shelf and the item sheet. No database change. |
| 2026-09-21 | SCAN-01 | `TODO` → `VALIDATING` | `resolveScan` (pure matcher for chemical/apparatus/legacy payloads), `RecentScan` + `recentScansProvider` (per-user shared-preferences history, deduped per item, capped at 30, merged safely with scans made while loading), `RecentScansSection` on the scanner page (open item, removed/unknown states, show all, confirmed clear). Unit tests for the matcher, JSON round trip, dedupe/cap, per-user persistence and restore; widget tests for the section. No database change. |
| 2026-09-21 | SCAN-02 | `TODO` → `VALIDATING` | `ScanBatch` (pure model: added / duplicate / unknown outcomes, counts, summary line), batch mode + finish button on the scanner page, `BatchSummary` sheet. Unit tests for the model and widget tests for the summary sheet (counts, repeated reads, open item, keep scanning / done). No database change. |
