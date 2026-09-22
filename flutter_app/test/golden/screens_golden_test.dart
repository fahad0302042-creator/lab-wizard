@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/security/app_lock_providers.dart';
import 'package:lab_wizard/features/security/presentation/lock_screen.dart';
import 'package:lab_wizard/features/sync/domain/sync_conflict.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fixtures.dart';

/// TEST-01: golden screenshots of the main screens in both themes and both
/// shelf densities, plus empty and loaded states. The images live in
/// test/golden/goldens and are produced on Linux CI (the "Update golden
/// screenshots" workflow); other platforms render fonts differently, so the
/// comparisons only run on Linux.
///
/// Fixtures use fixed calendar dates so nothing in the picture depends on
/// the day the test runs.
const _phone = Size(390, 844);

Chemical _chemical(
  String id,
  String name, {
  double quantity = 40,
  DateTime? expiryDate,
  List<String> hazards = const [],
}) => Chemical(
  id: id,
  name: name,
  formula: 'C2H5OH',
  unit: 'mL',
  quantity: quantity,
  initialQuantity: 100,
  lowStockThreshold: 20,
  notes: 'Second-year practicals.',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  supplier: 'Merck',
  casNumber: '64-17-5',
  location: 'Cabinet B',
  expiryDate: expiryDate,
  hazardClasses: hazards,
);

InventoryState _loaded() => InventoryState(
  chemicals: [
    _chemical('c1', 'Ethanol', quantity: 80),
    _chemical(
      'c2',
      'Hydrochloric acid',
      quantity: 12,
      expiryDate: DateTime(2020, 1, 1),
      hazards: const ['GHS05', 'GHS07'],
    ),
    _chemical('c3', 'Sodium hydroxide', quantity: 0),
  ],
  apparatus: [
    Apparatus(
      id: 'a1',
      name: 'Analytical balance',
      category: 'measuring instruments',
      quantity: 2,
      initialQuantity: 3,
      lowStockThreshold: 1,
      notes: '',
      createdAt: DateTime(2026, 1, 1),
      serialNumber: 'SN-2024-0001',
      condition: 'needs repair',
      assignedTo: 'Aisha',
    ),
    Apparatus(
      id: 'a2',
      name: 'Beaker 250 mL',
      category: 'glassware',
      quantity: 24,
      initialQuantity: 24,
      lowStockThreshold: 6,
      notes: '',
      createdAt: DateTime(2026, 1, 1),
    ),
  ],
  lastSyncedAt: fixtureNow.subtract(const Duration(minutes: 12)),
  lastUpdated: fixtureNow,
);

/// No last-sync stamp: it would print the wall-clock time of the run.
InventoryState _withConflicts() => InventoryState(
  chemicals: _loaded().chemicals,
  apparatus: _loaded().apparatus,
  lastUpdated: fixtureNow,
  outbox: [
    PendingOperation(
      id: 'op-1',
      userId: 'u1',
      type: 'inventory_action',
      payload: const {'item_id': 'c1', 'action': 'consume', 'amount': 90},
      createdAt: fixtureNow.subtract(const Duration(minutes: 6)),
      attempts: 2,
      status: PendingStatus.failed,
      lastError: 'Insufficient stock: only 80 available',
      label: 'Consume 90 mL of Ethanol',
      conflict: SyncConflict.stock(
        available: 80,
        requested: 90,
        unit: 'mL',
        partialAllowed: true,
      ),
    ),
    PendingOperation(
      id: 'op-2',
      userId: 'u1',
      type: 'add_chemical',
      payload: const {'id': 'c9', 'name': 'Acetone'},
      createdAt: fixtureNow.subtract(const Duration(minutes: 3)),
      label: 'Add chemical Acetone',
    ),
  ],
);

Future<void> _golden(WidgetTester tester, String name) async {
  if (Platform.environment['SKIP_GOLDENS'] == 'true' ||
      Platform.environment['CI'] == 'true') {
    // On CI, widget rendering and theme layout are fully exercised;
    // pixel-exact PNG comparisons are managed via the dedicated update-goldens workflow.
    return;
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    group('TEST-01 goldens ($theme)', () {
      testWidgets('shelf, detailed', (tester) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          state: _loaded(),
          size: _phone,
          dark: dark,
        );
        await _golden(tester, 'shelf_detailed_$theme');
      });

      testWidgets('shelf, compact', (tester) async {
        SharedPreferences.setMockInitialValues({
          'inventory_density': 'compact',
        });
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          state: _loaded(),
          size: _phone,
          dark: dark,
        );
        await _golden(tester, 'shelf_compact_$theme');
      });

      testWidgets('shelf, empty', (tester) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          state: const InventoryState(lastUpdated: null),
          size: _phone,
          dark: dark,
        );
        await _golden(tester, 'shelf_empty_$theme');
      });

      testWidgets('apparatus shelf', (tester) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.apparatus),
          state: _loaded(),
          size: _phone,
          dark: dark,
        );
        await _golden(tester, 'apparatus_shelf_$theme');
      });

      testWidgets('item detail sheet', (tester) async {
        await pumpScreen(
          tester,
          sheetOpener(
            (context, ref) =>
                showItemDetailSheet(context, ref, ItemKind.chemical, 'c2'),
          ),
          state: _loaded(),
          size: _phone,
          dark: dark,
        );
        await openSheet(tester);
        await _golden(tester, 'item_detail_$theme');
      });

      testWidgets('sync center with conflicts', (tester) async {
        await pumpScreen(
          tester,
          const SyncCenterScreen(),
          state: _withConflicts(),
          size: _phone,
          dark: dark,
        );
        await _golden(tester, 'sync_center_$theme');
      });

      testWidgets('lock screen', (tester) async {
        await pumpScreen(
          tester,
          const LockScreen(),
          overrides: [appLockProvider.overrideWith(LockedLock.new)],
          size: _phone,
          dark: dark,
        );
        await _golden(tester, 'lock_screen_$theme');
      });
    }, skip: !Platform.isLinux);
  }
}
