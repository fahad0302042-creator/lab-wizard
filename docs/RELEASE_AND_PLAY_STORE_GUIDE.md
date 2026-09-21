# Lab Wizard Android Release & Google Play Distribution Guide

This document defines the production release pipeline, private keystore management (RELEASE-01), and Google Play Console deployment procedures (RELEASE-02) for the Lab Wizard Flutter application.

---

## Part 1: Private Production Signing (RELEASE-01)

### Dual-Mode Signing Architecture

The application build system (`flutter_app/android/app/build.gradle.kts`) supports **dual-mode signing**:

1. **Development / Public Build Mode (Default)**:
   - When no production signing credentials are provided, Gradle signs the APK using `lab-wizard-github.jks` with alias `labwizard`.
   - This key is intentionally repository-visible to allow open-source forks, automated CI checks, and phone testers to install development builds without manual key setup.
2. **Production Mode (Automatic switch)**:
   - When production signing credentials are provided (either locally via `flutter_app/android/key.properties` or via GitHub Secrets in CI), Gradle automatically signs release artifacts with the owner's private keystore.
   - The private keystore is **never** committed to the Git repository.

### Step 1: Generating the Private Production Keystore

The repository owner generates an upload keystore on their local workstation using standard Java `keytool`:

```bash
keytool -genkeypair \
  -v \
  -keystore lab-wizard-production.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias labwizard-production \
  -storetype JKS
```

When prompted:
- Enter a secure store password.
- Enter your organization / developer details.
- Retain the chosen alias (e.g., `labwizard-production`) and password.

### Step 2: Configuring GitHub Actions Secrets

Convert the binary keystore file into a Base64 string for GitHub Actions:

```bash
# On Linux / macOS:
base64 -w 0 lab-wizard-production.jks > keystore_base64.txt

# Or on macOS without -w 0:
base64 -i lab-wizard-production.jks | tr -d '\n' > keystore_base64.txt
```

Navigate to your GitHub Repository:
**Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add the following four repository secrets:

| Secret Name | Value | Description |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | `(content of keystore_base64.txt)` | Base64-encoded upload keystore |
| `ANDROID_KEYSTORE_PASSWORD` | `(your keystore password)` | Keystore store password |
| `ANDROID_KEY_ALIAS` | `labwizard-production` | Key alias name |
| `ANDROID_KEY_PASSWORD` | `(your key password)` | Private key password |

Once these secrets are present, GitHub Actions (`.github/workflows/android-apk.yml` and `.github/workflows/flutter-branch-ci.yml`) will automatically decode the private keystore and sign both the Universal APK and the Android App Bundle (`.aab`).

### Step 3: Key Storage, Backup & Disaster Recovery

1. **Secure Storage**:
   - Store the original `lab-wizard-production.jks` in an encrypted password vault (e.g., Bitwarden, 1Password) or an offline air-gapped backup drive.
2. **Repository Protection**:
   - `flutter_app/android/.gitignore` explicitly blocks `key.properties`, `*.keystore`, and `*.jks` (except `lab-wizard-github.jks`).
3. **Upload Key Reset (Google Play App Signing)**:
   - Google Play uses **Play App Signing**. The app signing key is held by Google; the local key is strictly an *upload key*.
   - If the private upload key is ever permanently lost or compromised, the developer account owner can visit **Google Play Console** → **Setup** → **App integrity** → **Request upload key reset**, and upload a new certificate without losing any users or existing installations.

---

## Part 2: Google Play Store Distribution (RELEASE-02)

### Package Identity & Architecture

- **Application ID / Namespace**: `com.labwizard.lab_wizard`
- **Minimum SDK**: Android 5.0 (API level 21)
- **Target SDK**: Android 15 (API level 35) / latest Google Play target
- **Release Format**: Android App Bundle (`.aab`), built to `build/app/outputs/bundle/release/app-release.aab`.

### Build Verification & Artifacts

Every release workflow on `main` (`.github/workflows/android-apk.yml`):
1. Verifies code formatting (`dart format`).
2. Runs static analysis (`flutter analyze --fatal-infos`).
3. Runs the complete test suite (unit, widget, semantics, goldens, large-data performance).
4. Produces:
   - `Lab-Wizard-Android-1.0.<run_number>.apk` (Direct universal APK for side-loading).
   - `Lab-Wizard-Android-1.0.<run_number>.aab` (Signed Android App Bundle for Google Play Console).
5. Releases both artifacts under GitHub Releases.

### Google Play Console Data Safety & Privacy Answers

When filling out the Google Play Console **Data Safety** questionnaire, use the following exact declarations:

#### 1. Data Collection & Usage

| Data Category | Data Type | Collected? | Shared with Third Parties? | Purpose | Ephemeral? |
|---|---|---|---|---|---|
| **Personal info** | Email address | Yes | No | Account authentication & user inventory isolation | No (Stored in Supabase Auth) |
| **App activity / content** | User inventory records (Chemicals, Apparatus, Logs) | Yes | No | Core app functionality (Lab notebook & stock tracking) | No (Stored in Supabase Database) |
| **App info and performance** | Crash logs / Diagnostics | Optional (default OFF) | No | Debugging & diagnostics (OBS-01). Stored strictly on device for 14 days, scrubbed of all PII and inventory data. Never uploaded to remote servers. | Stored locally only |
| **Location** | - | No | No | Not collected | - |
| **Financial info** | - | No | No | Not collected | - |
| **Contacts / Photos** | - | No | No | Not collected | - |

#### 2. Security Practices
- **Data Encrypted in Transit**: Yes. All communication with Supabase uses TLS 1.2/1.3 (HTTPS and WSS).
- **Data Deletion Mechanism**: Yes. Users can request account and data deletion directly in the app (**Settings** → **Danger zone** → **Delete account**). This calls `public.delete_my_account()`, which cascades across all user records and tombstones.

#### 3. Declared Android Permissions

| Permission | Justification for Google Play Review |
|---|---|
| `android.permission.CAMERA` | Required solely for the live optical viewfinder to scan chemical QR codes, apparatus QR codes, and product barcodes. No images are saved, photographed, or uploaded. |
| `android.permission.POST_NOTIFICATIONS` | Used strictly for user-configured on-device notifications (low inventory levels, upcoming chemical expiration, overdue apparatus loans, calibration schedules). No marketing or remote push spam. |
| `android.permission.USE_BIOMETRIC` / `USE_FINGERPRINT` | Optional local application lock (SECURITY-01). Authenticates device credentials via Android Keystore. Biometric biometric tokens never leave the device. |
| `android.permission.INTERNET` | Communicates with the user's Supabase backend instance for inventory synchronization and authentication. |

### Upgrade Path (Development APK → Play Store)

1. **Signature Compatibility**:
   - Because Android enforces OS-level certificate verification, devices with a side-loaded development APK (signed with `lab-wizard-github.jks`) cannot be updated in-place by the Play Store APK (signed with Google Play App Signing key).
2. **Data Preservation**:
   - Lab Wizard inventory data is persisted in the shared Supabase cloud backend (with an offline SQLite cache).
   - Before upgrading to the Play Store build:
     a. If you have unsaved offline changes, open **Sync Center** and tap **Retry all** to flush the outbox, or export a CSV backup via **Settings** → **Export data**.
     b. Uninstall the development APK.
     c. Install the app from Google Play Store.
     d. Sign in with your existing Lab Wizard account. All chemicals, apparatus, and activity logs are automatically restored from Supabase.
3. **In-Store Future Updates**:
   - Subsequent updates delivered via Google Play Store update seamlessly in place, as `versionCode` is monotonically generated based on timestamp (`$(( $(date +%s) / 60 ))`).
