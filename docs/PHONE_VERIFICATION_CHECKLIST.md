# Lab Wizard Android Phone Verification & Acceptance Checklist

This checklist provides step-by-step instructions for physical device verification of all implemented roadmap items (**Milestones A through K**). Completing these checks transitions items in `FLUTTER_IMPROVEMENT_ROADMAP.md` from `VALIDATING` to `RELEASED`.

---

## Pre-Requisites & Installation

1. On your Android phone, open GitHub and navigate to the repository Actions:
   `https://github.com/fahad0302042-creator/lab-wizard/actions`
2. Download the newest signed APK artifact (e.g. `Lab-Wizard-Android-branch-54` or release APK).
3. Tap the downloaded file to install. If Android prompts, select **Allow installs from this source**.
4. Open **Lab Wizard** and sign in with your Supabase account credentials.

---

## Milestone A: Daily Usability & Inventory Speed

- [ ] **UX-01 (Compact / Detailed Mode)**:
  - Open the chemical shelf. Tap the view toggle in the action bar to switch between Detailed cards and Compact rows.
  - Verify compact rows display: item name, current quantity, unit, stock status badge, and use/damage shortcuts.
  - Close the app completely and reopen; verify the selected mode was persisted.
- [ ] **UX-02 (A–Z Quick Navigation)**:
  - On a shelf with multiple items, locate the alphabetical strip on the right edge.
  - Tap a letter (e.g., "S"); verify the list immediately jumps to the first matching item.
  - Verify letters with no matching inventory items appear visibly dimmed/disabled.
- [ ] **UX-03 (Sticky Search & Collapsing Header)**:
  - Scroll down through the chemical list.
  - Verify the top notebook header collapses smoothly, while search bar and filter chips stay reachable.
- [ ] **UX-04 (Undo Actions)**:
  - Swipe right on any chemical to consume 5 mL.
  - Tap **Undo** on the bottom snackbar.
  - Verify quantity returns to its previous value and the item activity history records the reversal.
- [ ] **BATCH-01 / BATCH-02 / BATCH-04 (Batch Actions)**:
  - Long-press any item to enter multi-select mode. Select 3 items.
  - Tap **Restock** in the bottom bar; enter amounts and confirm; check progress bar.
  - Select 5 items and tap **Delete**; verify the dialog requires typing `DELETE` before the button activates.
- [ ] **QR-01 (Selected Item QR Printing)**:
  - Select 2 chemicals in multi-select mode and tap **Labels**.
  - Select 40-per-A4 grid and tap **Print**; verify the Android print preview renders only the 2 selected QR codes.

---

## Milestone B: Import & Chemical Metadata

- [ ] **DUP-01 (Duplicate Detection)**:
  - Tap **+** to add a chemical with the exact same name as an existing chemical.
  - Verify an inline duplicate warning card appears with links to **View existing** or **Add anyway**.
- [ ] **FORM-01 (Form Memory)**:
  - Add a chemical with unit "g" and category "Acids". Save.
  - Tap **+** again; verify unit and category default to "g" and "Acids".
- [ ] **DATA-01 & DATA-02 (Chemical Metadata & Hazards)**:
  - Open a chemical and expand *more details*.
  - Enter a CAS number (e.g., `67-64-1`), select GHS hazard chips (`GHS02`, `GHS07`), and set an expiry date within 2 weeks.
  - Save and return to shelf: verify the "Expiring soon" badge and hazard icons appear.

---

## Milestone C: Apparatus Operations

- [ ] **GEAR-01 (Apparatus Metadata)**:
  - Add or edit an apparatus item (e.g. "Centrifuge 5424 R").
  - Add serial number, assigned custodian, and warranty expiration date.
- [ ] **GEAR-02 (Checkout & Return Loans)**:
  - Tap **Check out** on the apparatus details sheet.
  - Enter borrower name (e.g., "Dr. Smith"), quantity (1), and a due date.
  - Verify the active loan appears in the item's loans section.
  - Tap **Return** to close the loan and verify quantity is restored.
- [ ] **GEAR-03 (Maintenance & Calibration)**:
  - Schedule a "Calibration" task with a due date.
  - Mark it complete with result "Passed" and notes.
- [ ] **GEAR-04 (Apparatus History)**:
  - Check the apparatus history timeline; verify checkouts, returns, and calibration entries appear in chronological order.

---

## Milestone D: Proactive Notifications

- [ ] **NOTIFY-01..04 (Local Alerts & Summaries)**:
  - Open **Settings** → **Notifications**.
  - Toggle on low-stock alerts and expiry reminders.
  - Set a chemical quantity below its threshold; verify a local Android notification appears in the status bar.

---

## Milestone E: Sync Center & Offline Resilience

- [ ] **SYNC-01 (Sync Center)**:
  - Open **Settings** → **Sync & offline copy** → **Open sync center**.
  - Verify last sync timestamp, pending changes count, and conflict cards.
- [ ] **SYNC-02 & SYNC-03 (Offline Outbox & Background Sync)**:
  - Put phone in **Airplane Mode** (no Wi-Fi or cellular).
  - Consume stock from an item. Verify the change is saved locally in SQLite and tagged as pending in the sync center.
  - Re-enable Wi-Fi. Verify changes flush automatically to Supabase.
- [ ] **SYNC-04 (Conflict Handling)**:
  - If a server conflict occurs, verify the Sync Center explains the difference and offers options (*Apply what is left*, *Overwrite*, or *Discard*).

---

## Milestone F: Scanner & Barcode Integration

- [ ] **QR-02 & QR-03 (Apparatus Labels & Share)**:
  - Open an apparatus item sheet; tap **Share image** or **PDF**.
  - Verify the rendered 80 × 50 mm label contains QR code, apparatus name, serial number, and short ID.
- [ ] **SCAN-01 (Recent Scans)**:
  - Open **Scanner** tab; scan any valid chemical QR code.
  - Verify the scanned item is listed under *Recent scans* below the viewfinder.
- [ ] **SCAN-02 (Batch Scanning)**:
  - Switch scanner toggle from *Single* to *Batch*.
  - Scan multiple QR codes continuously without leaving the camera. Tap **Finish** and check summary counts.
- [ ] **SCAN-03 (Scan and Act)**:
  - In single scan mode, scan an item; verify the compact action sheet appears with *Use*, *Restock*, and quick-amount chips.
- [ ] **SCAN-04 (External Product Barcodes)**:
  - Enable *Also read product barcodes* in scanner options.
  - Scan a commercial UPC/EAN bottle barcode. Tap **Link to item…** and link it to an existing chemical.
  - Scan the same UPC barcode again; verify it opens the linked chemical immediately.

---

## Milestone G: Reports & Exports

- [ ] **REPORT-01 & REPORT-02 (Date Ranges & Trends)**:
  - Open **Reports** tab. Switch between *This month*, *Last month*, and *Custom range*.
  - Verify activity chart and consumption percentage changes update accurately.
- [ ] **REPORT-03 (Run-Out Predictions)**:
  - Check the *Run-out estimates* card. Verify items with high consumption show estimated days remaining.
- [ ] **REPORT-05 & REPORT-06 (CSV & Branded PDF)**:
  - Go to **Settings** → **Lab profile**; set laboratory name and upload a logo image.
  - Return to Reports and tap **Share PDF report**. Verify the exported document includes your lab branding.
  - Tap **Export CSV** and open in Google Sheets / Excel; verify numbers and text formatting are clean and injection-safe.

---

## Milestone H: Security, Account & Production Release

- [ ] **SECURITY-01 (App Lock & Biometrics)**:
  - Go to **Settings** → **App lock**. Set a 4-digit PIN.
  - Enable fingerprint / face unlock.
  - Press phone Home button to background the app. Reopen Lab Wizard.
  - Verify the lock overlay appears and unlocks cleanly with fingerprint or PIN.
- [ ] **ACCOUNT-01..04 (Account Management & Scoped Sign-Out)**:
  - Test password change in **Settings** → **Your account**.
  - Verify active device session details in **Settings** → **Sessions & devices**.
  - Test **Sign out other devices** and **Sign out (this phone)**.
- [ ] **RELEASE-01 & RELEASE-02 (Production Signing & Play Bundle)**:
  - Review [`docs/RELEASE_AND_PLAY_STORE_GUIDE.md`](RELEASE_AND_PLAY_STORE_GUIDE.md).
  - Verify the workflow generates both `.apk` and `.aab` artifacts in GitHub Actions.

---

## Milestone I: Accessibility & Quality

- [ ] **A11Y-01 (TalkBack)**:
  - Enable Android TalkBack (**Settings** → **Accessibility** → **TalkBack**).
  - Touch a chemical card. Verify TalkBack reads: *"Item name, quantity with unit, stock status in words, hazards, custom actions available"*.
  - Swipe up/down to access TalkBack actions (*Use*, *Restock*).
- [ ] **A11Y-02 (200% Large Text)**:
  - Set Android Font Size to maximum (**Settings** → **Display** → **Font size: Largest**).
  - Inspect shelf cards, detail sheets, and dashboard; verify zero text truncation or RenderFlex layout overflows.
- [ ] **A11Y-03 (Orientation & Responsive Layout)**:
  - Rotate phone to landscape mode.
  - Verify shelf heading collapses smoothly and items display in a spacious grid without overlapping.
- [ ] **A11Y-04 (Color-Blind Accessibility)**:
  - Inspect stock progress bars: verify healthy (sparse stripes), low stock (dense stripes), and empty (cross-hatch) are visually distinct without relying solely on color.
- [ ] **A11Y-05 (Reduced Motion & Touch Targets)**:
  - Enable **Remove animations** in Android Accessibility settings.
  - Open app; verify all count-ups, dialogs, and scanner sweeps appear instantly without lag or animations.
- [ ] **OBS-01 (Opt-in Crash Diagnostics)**:
  - Go to **Settings** → **Crash reports**; toggle ON.
  - Verify scrubbed report preview redacts email addresses, item names, and tokens.

---

## Milestone K: Multi-Lab & Organizations

- [ ] **ORG-01..04 (Lab Switcher & Workspace Isolation)**:
  - On the Dashboard, tap the `Personal Lab ▾` chip beneath the greeting.
  - Verify the modal sheet opens showing "Personal Lab" and "Create new organization…".
  - Tap **Create new organization…**; enter organization name (e.g. "University Chemistry Dept") and initial lab ("Organic Lab 201").
  - Switch between **Personal Lab** and the newly created lab; verify the chip updates and inventory queries are scoped to the active workspace.
  - Open **Settings** → **Organization & labs** card; verify active role badge is displayed.

---

### Sign-off

| Milestone | Tester Name | Date Verified | Result (Pass / Fail) |
|---|---|---|---|
| Milestone A (Usability) | | | |
| Milestone B (Import / Metadata) | | | |
| Milestone C (Apparatus) | | | |
| Milestone D (Notifications) | | | |
| Milestone E (Sync / Offline) | | | |
| Milestone F (Scanner / QR) | | | |
| Milestone G (Reports / PDF) | | | |
| Milestone H (Security / Auth) | | | |
| Milestone I (Accessibility) | | | |
| Milestone K (Multi-Lab) | | | |
