# Lab Wizard

A chemistry-lab inventory system. One account, one set of data, two clients:
the Next.js web app in the repository root and the Android app in
[`flutter_app_v2/`](flutter_app_v2/DESIGN.md).

Both talk to the same Supabase project, so a reagent logged on the phone shows
up on the web and the other way round. No inventory has to be entered twice.

## Install on Android without a PC

1. Open this repository in the GitHub app or your phone browser.
2. Open **Releases**.
3. Open the newest **Lab Wizard** release — the one marked *Latest*.
4. Download the file named `Lab-Wizard-Android-*.apk` under **Assets**.
5. Open the downloaded APK.
6. If Android asks, allow your browser or GitHub app to **install unknown apps**.
7. Install it and sign in with the same Lab Wizard email and password.

The build stamp at the bottom of the sign-in screen must match the release you
downloaded (`build 2.0.N`). If it does not, an older build is still installed.

Future APKs use the same GitHub development signing key, so they install as
updates without deleting the app. Supabase remains the source of truth for
synced data.

> The repository-visible signing key is intended only for direct GitHub
> development builds. A Play Store release must use private Play App Signing
> credentials.

## What the Android app is

An instrument panel, not a form. Each reagent stands in a glass vessel whose
liquid *is* its stock level, and whose colour is the thing that decides whether
it needs attention:

| Level | Decided by | Shown as |
|---|---|---|
| how full | `quantity ÷ max(initialQuantity, quantity)` | liquid height |
| needs attention | your order level | sage / clay / berry |

The order-level notch is drawn on the glass at `limit ÷ quantity-held`, so the
line and the liquid can never disagree — including when the phone is tilted and
the liquid leans. The gyro drives that lean; it can be switched off, and
reduced motion switches it off with it. Nothing about the app depends on it.

Full design contract: [`flutter_app_v2/DESIGN.md`](flutter_app_v2/DESIGN.md).

## Automatic Android releases

[`.github/workflows/android-apk.yml`](.github/workflows/android-apk.yml):

1. builds a signed universal APK,
2. reports formatting and runs static analysis and tests,
3. uploads the APK as an Actions artifact, and
4. publishes it under GitHub Releases when the build is from `main`.

A pull request that touches the app also builds an APK and attaches it to the
run, so a change can be installed and felt on a phone before it lands. Branch
builds never publish a release and never take the *Latest* badge, so the
download link above cannot turn into a test build.

[`.github/workflows/flutter-checks.yml`](.github/workflows/flutter-checks.yml)
is the hard gate on every pull request: `flutter analyze` and `flutter test`,
with the full output posted as a comment.

Both can be started from **Actions → Run workflow**, which works from a phone
browser.

## Data compatibility

The APK is compiled with the same public Supabase project configuration as the
web app. Row Level Security restricts each signed-in user to their own rows. The
public anonymous API key is not a service-role secret and is already shipped to
both clients.

The Android app keeps a per-user SQLite cache and a pending-operation outbox.
Cached private data is cleared on sign-out, but the outbox is kept: queued
changes are the user's work.

For atomic, retry-safe inventory updates, apply the additive migration at:

[`flutter_app_v2/supabase/001_inventory_actions.sql`](flutter_app_v2/supabase/001_inventory_actions.sql)

It adds columns, constraints, an idempotency index and the
`apply_inventory_action` RPC the app calls. It removes and renames nothing used
by the web app. Until it is installed, the app falls back to a compatibility
path against the existing schema.

## Web app

See [`SUPABASE_SETUP.md`](SUPABASE_SETUP.md) for the original web setup notes.
The web app source is in `src/`.

## History

The first Flutter client has been retired and removed from the repository: the
app in `flutter_app_v2/` replaced it feature for feature. Its APKs are still on
the Releases page under the *Lab Wizard (old app)* titles, and its transactional
SQL was moved to `flutter_app_v2/supabase/` because the current app is its only
caller. Install the app in `flutter_app_v2/`; the old one is kept only so an
existing install can be compared against it.
