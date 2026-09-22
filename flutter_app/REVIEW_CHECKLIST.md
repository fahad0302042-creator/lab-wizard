# Lab Wizard Flutter — what to check

Device and Supabase checks for this branch. GitHub Actions (`Flutter branch CI`) formats, analyzes, tests, and builds a signed APK. Tick a device item only after you have confirmed it on a phone or in Supabase.

## Fixed in this tree — confirm on a device or in Supabase

### 1. Widget Undo waits for the lock, then asks

- **Where:** `lib/features/home/presentation/home_shell.dart`, `lib/features/widgets/widget_link.dart`
- **Check:** Turn the PIN on. Leave the app. Tap Undo on the widget. The last entry must still be there while the lock screen is up. After you unlock, a dialog asks before anything changes. Cancel must leave the quantity alone.

### 2. Another app cannot open `labwizard://undo`

- **Where:** `android/app/src/main/AndroidManifest.xml` (no browsable `labwizard` filter), `MainActivity.kt` (private `launch_token`)
- **Check:** From another app, start Lab Wizard with data `labwizard://undo` or extra `deep_link_uri=labwizard://undo` and no matching token. The app may open. It must not undo stock.
- **Also check:** After a rebuild, the widget's Scan, Search, Undo, and item rows still open this app. Those PendingIntents are explicit and carry the token.

### 3. Sign-out clears the widget

- **Where:** `lib/app/providers.dart` (`clearWidget`), `MainActivity.kt`
- **Check:** Sign in, use a chemical, confirm the widget shows its name. Sign out. The launcher must not keep that name. A signed-out cold start should clear it too.

### 4. Flaskie tap is not a public broadcast

- **Where:** `FlaskieTapReceiver.kt` (`android:exported="false"`), widget provider ignores `ACTION_FLASKIE_TAP` on the exported receiver
- **Check:** `adb shell am broadcast -a com.labwizard.lab_wizard.ACTION_FLASKIE_TAP` must not cycle the bubble. Tapping Flaskie on the widget still should.

### 5. Multi-lab SQL is rewritten — do not assume it is applied

- **Where:** `supabase/010_multi_lab_organizations.sql` (section 5), `supabase/009_account_deletion.sql`
- **What changed in the script:**
  - Membership checks are `SECURITY DEFINER` helpers. Policies no longer query their own tables.
  - Apparatus can be updated and deleted by a lab writer. Chemicals can be deleted by a lab writer. Viewers can read, not write.
  - A shared row cannot be detached into a personal notebook.
  - `apply_inventory_action` / `undo_inventory_action` allow a lab writer as well as the row owner. Undo still only reverses the caller's own log.
  - `organizations.created_by` is `ON DELETE RESTRICT`. Deleting an account transfers a shared org to another member, deletes a sole-owned org, and reassigns shared shelf rows before `auth.users` is deleted.
  - `create_organization_with_lab` is revoked from `public` / `anon`.
- **Check:** In the Supabase SQL editor, run `010`, then `009`. Then:
  - `select * from organization_members` as a member must not error with infinite recursion.
  - Create an org, add a second member, delete the creator's account (or call `delete_my_account` as the creator). The org and the other member's access must remain.
  - A personal consume on your own bottle must still work. That path did not change.
- **Order if you re-run older scripts:** `001` and `002` install owner-only stock functions. Re-run `010` after either of them. Re-run `009` after `010`.

### 6. Failed org create shows an error

- **Where:** `lib/features/organizations/presentation/lab_switcher_sheet.dart`
- **Check:** Create an organization while offline, or with a slug that already exists. A snackbar must say it failed. It used to fail silently.

### 7. A late lab restore cannot overwrite a tap

- **Where:** `lib/features/organizations/presentation/organization_providers.dart`
- **Check:** With a saved team lab, tap Personal Lab as soon as the switcher opens. The chip must stay on Personal Lab.

### 8. The selected lab scopes the shelf

Run `supabase/010_multi_lab_organizations.sql` first, then pull to refresh. Personal Lab shows only rows with no lab. A team lab shows only rows with that lab's id, including a teammate's shared rows. The scanner, reports and home-screen widget follow the same choice. A new item, including a CSV import, is stamped with the active lab. A viewer can open the shelf but cannot consume, edit, lend or delete. A member can change stock but not delete. That follows the lab currently selected, so switch back to Personal Lab before changing a personal item. For a moment after sign-in, while a saved lab is loading, changes are refused instead of landing in the wrong notebook. Alerts and the account backup still include every cached row, so an alert can open an item that is not on the current shelf. Confirm a personal bottle disappears from the list when you pick a team lab, and comes back when you pick Personal Lab.

## Still open — do not treat these as done

### 9. GitHub signing key can update sideloaded installs

`android/app/build.gradle.kts` still signs release builds with the committed `lab-wizard-github.jks` unless Play secrets are set. Anyone with the repo can sign an update over that sideload. Uninstall it before using real lab data.

### 10. Password reset is still a custom scheme

`com.labwizard.labwizard://reset-password` can be claimed by another app. PKCE limits the damage. An HTTPS App Link is the improvement, not done here.

### 11. Local version and an unused dependency

`pubspec.yaml` is still `1.0.0+1` and still depends on unused `go_router`. CI overrides the version. A local build does not.

### 12. Large files

`inventory_screen.dart`, `inventory_sheets.dart`, and `lib/app/providers.dart` are still doing too many jobs. Leave them until the next feature that has to touch them.

## Already solid — no change in this pass

Auth password checks, offline outbox, incremental sync, field-level conflicts, CSV formula protection, PIN hashing, opt-in diagnostics scrubbing, and the accessibility tests.
