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

## Web app

See [`SUPABASE_SETUP.md`](SUPABASE_SETUP.md) for the original web setup notes. The web app source remains in `src/`.
