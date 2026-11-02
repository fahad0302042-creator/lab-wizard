# Lab Wizard — Flutter app review

Reviewed: everything under `flutter_app/lib` (7,336 lines, 18 files), `test/`, `pubspec.yaml`,
`analysis_options.yaml`, Android manifest + Gradle signing, and `.github/workflows/android-apk.yml`.

**How this was reviewed, and its limits.** There is no Flutter/Dart SDK in this sandbox and
`pub.dev` / `storage.googleapis.com` are not reachable, so I could **not** run
`flutter analyze`, `flutter test`, or a build. Everything below is from reading the code.
I flag the two places where I'm inferring rather than confirming.

**Verdict.** This is a well-structured app. Feature-first layout, Riverpod notifiers instead of
`setState` spaghetti, an offline cache + outbox that actually exists, idempotent RPC with a
graceful schema-mismatch fallback, and a notebook theme applied consistently rather than
sprinkled. The weak spot is not the UI layer — it's **offline/sync correctness**, where a few
paths can silently lose or revert the user's data. That's where I'd spend the next work.

---

## P0 — data loss / correctness

### 1. Signing out deletes unsynced work, silently

`AuthController.signOut` (`lib/app/providers.dart:130-142`) calls
`localDatabase.clearUser(userId)`, and `clearUser` (`lib/core/database/local_database.dart:158-168`)
deletes **both** `cache_records` and the `outbox`.

So if a user records usage while offline (the app explicitly supports and advertises this) and
then signs out — switching accounts, or just tidying up — those pending operations are gone with
no warning. The dashboard even shows "N changes waiting to sync" right up until the moment they're
destroyed.

Fix: keep the outbox on sign-out (it's keyed by `user_id`, so it can't leak across accounts),
or block sign-out with a confirm dialog when `pendingCount > 0`.

### 2. A failed sync followed by a refresh visually reverts the user's edits

`syncPending` (`lib/features/inventory/data/inventory_repository.dart:398-429`) stops at the
**first** failed operation (`break`, line 425) and returns the remaining count.

`refresh` (`:53-83`) then calls `replaceRecords` for chemicals, apparatus **and logs**, which
wipes the entire local cache and replaces it with server rows.

Chain: one operation fails for any reason (a constraint, a deleted item, a schema mismatch) →
users keep using the app offline → they pull to refresh on flaky Wi-Fi → the optimistic
quantities and their pending log rows are replaced by stale server state. The outbox still has
the operations, so it *eventually* corrects itself, but in between the UI shows wrong numbers
and the user's entry looks lost.

Fixes, in order of value:
- Don't `replaceRecords` records that have pending operations; merge instead (server rows win
  everywhere except items referenced by an unfired outbox entry).
- `continue` past a poison operation rather than `break`, and park it (`attempts` already exists
  and `markAttempt` already increments it — nothing ever reads it).
- After N attempts, surface a "1 change couldn't sync — tap for details" affordance.

### 3. `deleteItem` is not atomic and has no idempotency

`inventory_repository.dart:380-396` deletes from `consumption_logs`, then from the item table,
as two separate un-awaited-together calls.

If the second call fails, the audit history is gone but the item remains — a half-deleted row
the app will happily keep showing. And unlike `applyAction`, delete has no RPC, no outbox, and
no offline path (it throws `StateError('Deleting items requires a connection.')`).

Fix: one RPC that deletes logs + item in a transaction (you already own
`flutter_app/supabase/001_flutter_safe_actions.sql`, so this is additive), plus an
`delete_item` outbox type.

### 4. Absolute-quantity fallback can clobber a concurrent edit

`_compatibilityAction` (`:325-363`) is the path used when the transactional RPC isn't installed.
It writes `new_quantity`, an **absolute** value computed from `previousQuantity` captured on this
device. Two devices (phone + web, which this repo explicitly supports) consuming the same
reagent: the second write silently overwrites the first.

The RPC path is correct (it applies a delta server-side). So this is really an argument for
treating the migration as required rather than optional — or for changing the fallback to a
read-modify-write on the fresh server value instead of the cached one.

---

## P1 — real bugs, smaller blast radius

| # | Issue | Where |
|---|---|---|
| 5 | `InventoryState.copyWith` has `error: error` with a `null` default, so **every** `copyWith` clears the error banner — including `addChemical`, which passes no error at all. Offline notices vanish when you add an item. Needs a sentinel or an explicit `clearError` flag. | `providers.dart:226-246` |
| 6 | `applyAction` uses `state.chemicals.firstWhere(...)` with no `orElse`. If the item was deleted on another device and you still have a sheet open on it, this throws an unhandled `StateError`. | `providers.dart:407-409` |
| 7 | Batch consume runs one `applyAction` per item in a loop (`inventory_sheets.dart:757-770`). If item 3 of 5 fails, items 1-2 are recorded, the sheet stays open, and the snackbar says nothing about the partial result. Either pre-flight all validation (it partly does) or report "2 of 5 recorded". | `inventory_sheets.dart:742-786` |
| 8 | Batch consume hard-codes the note `'Batch consume'` (`:768`) and always uses `DateTime.now()`. Every other entry point lets the user write a note and backdate. | `inventory_sheets.dart:768` |
| 9 | `LocalDatabase` is `version: 1` with **no `onUpgrade`**. The first time anyone adds a column or table, existing installs throw on open rather than migrating. Cheap to fix now, painful later. | `local_database.dart:13-45` |
| 10 | Scanner: `_handling` is only reset on the success and "not found" paths. Any throw from `showItemDetailSheet` or from `_scanner.start()` leaves `_handling == true` and the scanner dead for the rest of the session. Also `_scanner.start()` is called after `stop()` without a `mounted` guard on the controller itself. | `scanner_screen.dart:346-380` |
| 11 | Logs are loaded and cached **unbounded** (`select()` with no limit, `:60-64`). At a few entries per day this is thousands of rows pulled into memory and JSON-encoded into SQLite on every refresh. Cap the window (e.g. last 12 months / 500 rows) and query per-month for reports. | `inventory_repository.dart:57-64` |

---

## P2 — parity gaps vs. the web app

The web client has several things the Android client doesn't. Some are deliberate simplifications;
these look like omissions rather than decisions:

- **Undo.** The web app offers a 5-second undo on every logged action
  (`src/components/modals/chemical-modals.tsx:311-325`). Flutter records and shows a plain
  snackbar (`inventory_sheets.dart:1008-1015`). Undo matters *more* on a phone — fat-fingering
  "consume 50" is easy, and there's no way back without editing the log.
- **Editing / deleting a log entry, and clearing a month.** `updateLog`, `deleteLog`, `clearMonth`
  all exist in the web store; nothing equivalent in Flutter. A mistyped entry is permanently wrong.
- **Reset-all-data.** Web has `resetAll` in Settings. Flutter's Settings has no destructive option
  at all, which is arguably fine — but it means no way to recover from a bad bulk import.
- **Recent scans.** `pushRecentScan` exists on web; the Flutter scanner keeps no history, so
  re-finding the thing you just scanned means scanning it again.
- **Forgot password.** Neither client has it, but on a phone there is no "go use the web app"
  fallback, so this bites harder here.
- **Realtime.** Neither client subscribes to Supabase changes. With both clients advertised as
  live views of the same data, a second device only appears after a manual pull-to-refresh. A
  `Realtime` channel on `chemicals` / `apparatus` / `consumption_logs` filtered by `user_id`
  would close this, and it pairs naturally with the pending-operation merge in P0-2.

---

## P3 — code health

- **Three dead dependencies.** `go_router` (`pubspec.yaml:38`), `connectivity_plus` (`:43`) and
  `cupertino_icons` (`:36`) are declared and never imported anywhere in `lib/` or `test/`.
  `mocktail` (`:66`) is declared but no test uses it. Navigation is raw `Navigator.push`, and
  there is **no connectivity awareness at all** — the app discovers it's offline by catching an
  exception, which is why `_isConnectivityError` (`inventory_repository.dart:451-459`) has to
  string-match error text. Either drop the deps or actually use them: a `connectivity_plus`
  stream driving the outbox retry would remove a lot of guesswork.
- **The same private extension, five times.** `extension<T> on Iterable<T> { get firstOrNull }`
  is copy-pasted into `dashboard_screen.dart:906`, `inventory_repository.dart:466`,
  `inventory_sheets.dart:1357`, `reports_screen.dart:581`, `scanner_screen.dart:431`. You already
  depend on `collection`, which provides it. One import, five deletions.
- **`stockProgress` fights itself.** `models.dart:58-65` uses `lowStockThreshold * 2` as the "full"
  target. Set a threshold above half the initial quantity (perfectly reasonable: 500 mL bottle,
  warn at 300) and the bar can never fill — it shows ~60% on a brand-new unopened bottle.
  Threshold and capacity are different concepts; derive the bar from `initialQuantity` and mark
  the threshold separately.
- **Status vocabulary drifted.** Flutter has `StockState { healthy, low, empty }` (`models.dart:9`)
  while web has `healthy | low | critical | empty`. The Flutter filter chip labelled "critical"
  actually means *empty* (`inventory_screen.dart:393-395`). Harmless today; confusing the first
  time someone reads both codebases.
- **Dead ternary.** `inventory_screen.dart:608-610`: `kind == chemical ? marginRed : marginRed`.
- **Unused parameters.** `showBatchConsumeSheet(BuildContext, WidgetRef _)` ignores the ref it's
  handed (`inventory_sheets.dart:74`). `PageHeading('quick actions', trailing: SizedBox.shrink())`
  (`dashboard_screen.dart:225`, also `scanner_screen.dart:233`) exists only to defeat a default —
  give `PageHeading` a nullable trailing instead.
- **Error handling is silent in places.** `_printQrLabels` (`inventory_screen.dart:399-440`) has a
  `finally` but **no** `catch`: a PDF failure surfaces as an unhandled async error with the button
  silently re-enabling. Everywhere else in the app you show a friendly snackbar; this one path
  should too.
- **`_friendlyError` is private to `inventory_sheets.dart`** (one definition, five call sites —
  *corrected: I first wrote that it was copied across three sheets; it isn't*). Because it's
  private, the screens can't reuse it, which is why `inventory_screen.dart` had no friendly
  error path at all for printing. Worth promoting to `core/`.

---

## P4 — accessibility & polish

- Only **3 `Semantics(...)` wrappers** in 7,300 lines. Tappable card surfaces (`NotebookCard`,
  `_CardAction`, filter words) are `InkWell`/`GestureDetector` with no `button: true`, so
  TalkBack announces them as plain text. The bottom nav and the two swipe backgrounds are the
  only properly labelled things.
- **Touch targets under 48 dp.** `_CardAction` is a 16 px `Text` with 5 px vertical padding
  (~26 dp). Filter chips and the `batch consume` / `print QR labels` text buttons set
  `tapTargetSize: shrinkWrap`. That's below both Material and WCAG guidance, and these are the
  most-tapped controls in the app.
- **Text scaling is clamped to 1.5×** (`app.dart:28`), which helps, but the layout was clearly
  designed at 1.0. I can't confirm overflow without running it — worth a manual pass at 1.5×
  and 2.0× on the dashboard KPI grid (`childAspectRatio: 1.45`), the bottom nav's fixed
  `height: 70`, and the inventory card's two-line header. This is the one item where I'm
  inferring rather than observing.
- **Body text at 11-12 px** in several captions (`min 20 mL`, `12 of 14`, activity timestamps).
  Fine on a Pixel at 1.0; uncomfortable on a tablet at arm's length.
- **No localization.** All strings are inline. `intl` is already a dependency, and this is a lab
  app in Pakistan — Urdu/RTL is a plausible near-term request, and retrofitting strings later is
  much worse than extracting them now.
- **Release keystore password is plaintext in Gradle** (`android/app/build.gradle.kts:17-24`:
  `storePassword = "labwizard-github"`). The README justifies publishing the key for
  direct-GitHub installs, and that reasoning is sound for a dev build — but the *password* could
  still come from an env var or `key.properties` without breaking that story. Also worth a note
  that anyone who clones this repo can sign an APK that Android will accept as an update to an
  installed Lab Wizard.

---

## P5 — testing & CI

- **Four tests, ~50 lines.** `models_test.dart` covers `stockState`, day keys and formatting —
  good, and exactly the right things. `app_smoke_test.dart` renders the app and asserts the
  "backend not configured" screen. Nothing covers the **repository**, the outbox, the merge/order
  logic, or `InventoryController` — which is precisely where P0-1 through P0-4 live. `mocktail`
  is installed and unused; `LocalDatabase` is already easy to fake behind its own interface.
- **CI never runs on pull requests.** `.github/workflows/android-apk.yml` triggers on
  `push: branches: [main]` and `workflow_dispatch` only. So this review can't be backed by
  `flutter analyze --fatal-infos` on the current branch, and neither can any future change —
  a broken `lib/` file is discovered only after it merges to `main`. A second workflow on
  `pull_request` running `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`
  and `flutter test` is ~25 lines and pays for itself immediately.
- The lints are stock `flutter_lints`. Adding a handful — `prefer_const_constructors`,
  `require_trailing_commas`, `avoid_dynamic_calls`, `unawaited_futures` — would catch most of
  what I listed in P3 mechanically. `unawaited_futures` in particular would flag the un-batched
  deletes in P0-3.

---

## What I'd do, in order

**Batch 1 — stop losing data (small, high value).**
Keep the outbox across sign-out (or block sign-out when pending). Merge instead of replace on
refresh. `continue` past poison ops and surface failed ones. Add `onUpgrade` to the local DB.
Fix the scanner's `_handling` leak. Fix `copyWith` clearing errors.

**Batch 2 — the two features users will actually feel.**
Undo on consume/restock/breakage (reuse the existing `applyAction` inverse). Realtime
subscription + connectivity-driven outbox retry, which also retires `_isConnectivityError`.

**Batch 3 — make it maintainable.**
Delete the 3 dead deps + duplicated extension; extract `_friendlyError`; add the PR CI workflow
and repository/outbox tests; then the accessibility pass (semantics + 48 dp targets).

Happy to start anywhere — say the word and I'll implement a batch on this branch.

---

## Batch 3 — applied on branch `arena/8ec51fe0-lab-wizard`

**Cleanup**

- Removed the four unused dependencies: `go_router`, `connectivity_plus`, `cupertino_icons`,
  `mocktail`. `pubspec.lock` still lists them until the next `flutter pub get` — that command
  prunes them automatically, and the APK workflow runs it first thing.
- Deleted the five copy-pasted `firstOrNull` extensions and imported
  `package:collection/collection.dart` (already a direct dependency) instead.
- Promoted `_friendlyError` out of `inventory_sheets.dart` into
  `lib/core/error_text.dart` as `friendlyError`, and pointed the existing five call sites at it.
- Removed the dead `marginRed : marginRed` ternary in `inventory_screen.dart`.
- Dropped the `trailing: SizedBox.shrink()` hacks — `PageHeading`'s `trailing` is already
  nullable.

**Accessibility / touch targets**

- `NotebookCard` now wraps its `Material` in `Semantics(button: onTap != null)`, so tappable
  cards are announced as buttons rather than plain text.
- `_CardAction` (the `use` / `+ stock` links) is now a semantics button inside a
  44 × 44 minimum box — it was a 16 px label in ~26 dp of padding.
- `NotebookFilterWord` keeps its hand-written look but gets a 44 dp tap box.
- Removed all three `tapTargetSize: MaterialTapTargetSize.shrinkWrap` overrides (the two
  utility buttons in the chemicals screen and `CircledNotebookButton`), so they fall back to
  Material's 48 dp minimum.

**Error handling**

- `_printQrLabels` had a `finally` but no `catch`: a PDF/printing failure escaped as an
  unhandled async error while the button silently re-enabled. It now shows the standard
  friendly snackbar. (This is the "only catch block added" — the rest of the app's error
  handling was already in good shape.)

**CI**

- Added `.github/workflows/flutter-checks.yml`: on any pull request touching `flutter_app/**`
  it runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and
  `flutter test`, with the same Flutter 3.47.4 pin as the release workflow.

**Tests**

- Added `test/models_roundtrip_test.dart`: map round trips for chemicals, apparatus and logs
  (including numeric columns arriving as strings, and an unknown `action` degrading to
  `consume` instead of throwing), plus `stockProgress`/`formatQuantity` invariants. Safe,
  mock-free tests over code paths that were previously untested.

**Not done, deliberately**

- The stricter lint set (`unawaited_futures`, `avoid_dynamic_calls`,
  `require_trailing_commas`) — enabling it now would fail `--fatal-infos` on existing code.
  That's a separate pass with the fixes.
- `connectivity_plus` was removed rather than wired up. If you take the sync batch
  (P0-2 / realtime), it comes back — but as code that's actually used, driving the outbox
  retry instead of the string-matched `_isConnectivityError`.

**One caveat on this batch.** This sandbox has no Dart SDK, so none of the above was run
through `dart format`, `flutter analyze` or `flutter test`. I wrote the changes to match the
surrounding formatting by hand and checked that no new line exceeds 80 columns, but if the new
CI goes red it will most likely be the formatter asking for a reflow — `dart format lib test`
in `flutter_app/` fixes it.
