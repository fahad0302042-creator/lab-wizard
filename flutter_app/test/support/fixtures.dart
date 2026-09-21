import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/security/app_lock_providers.dart';
import 'package:lab_wizard/features/security/domain/app_lock.dart';

/// Shared fixtures for the layout audits (A11Y-02 large text, A11Y-03
/// widths and orientations): a rich inventory with long names and every
/// metadata field filled, plus a pump helper that sets the viewport and
/// text scale.
const maxTextScale = 2.0;
const smallPhone = Size(360, 740);

class SeededInventory extends InventoryController {
  SeededInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> bootstrap(String userId) async {}

  @override
  Future<void> refresh() async {}
}

/// A lock that is already set up and locked, without touching storage.
class LockedLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(
    ready: true,
    enabled: true,
    pinLength: 4,
    biometrics: true,
    biometricsAvailable: true,
    locked: true,
    throttle: LockThrottle.none,
  );
}

final fixtureNow = DateTime.now();

Chemical chemicalFixture(
  String id,
  String name, {
  double quantity = 12345.5,
  double threshold = 250,
}) => Chemical(
  id: id,
  name: name,
  formula: 'C6H5CH2CH(NH2)COOH',
  unit: 'mL',
  quantity: quantity,
  initialQuantity: 20000,
  lowStockThreshold: threshold,
  notes: 'Keep away from oxidisers. Stored in the flammables cabinet.',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  supplier: 'Merck Life Science Pakistan (Pvt.) Limited',
  casNumber: '64-17-5',
  concentration: '99.8 % v/v',
  location: 'Flammables cabinet, shelf 2, bench 3',
  expiryDate: fixtureNow.add(const Duration(days: 10)),
  hazardClasses: const ['GHS02', 'GHS06', 'GHS07', 'GHS08'],
  barcode: '4006381333931',
);

Apparatus apparatusFixture(String id, String name) => Apparatus(
  id: id,
  name: name,
  category: 'measuring instruments',
  quantity: 3,
  initialQuantity: 12,
  lowStockThreshold: 4,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  serialNumber: 'SN-2024-000123-XL',
  condition: 'needs repair',
  assignedTo: 'Dr. Aisha Rahman-Qureshi',
  location: 'Instrument room',
  purchaseDate: DateTime(2024, 5, 1),
  warrantyUntil: fixtureNow.add(const Duration(days: 20)),
);

ConsumptionLog logFixture(String id, String itemId, int daysAgo, {double amount = 250}) =>
    ConsumptionLog(
      id: id,
      itemId: itemId,
      itemType: ItemKind.chemical,
      action: InventoryAction.consume,
      amount: amount,
      note: 'Titration practical, second year',
      loggedAt: fixtureNow.subtract(Duration(days: daysAgo, hours: 2)),
      createdAt: fixtureNow.subtract(Duration(days: daysAgo, hours: 2)),
    );

InventoryState richState() => InventoryState(
  chemicals: [
    chemicalFixture('c1', 'Hydrochloric acid concentrated (37 %)'),
    chemicalFixture('c2', 'Ethanol', quantity: 80),
    chemicalFixture('c3', 'Sodium hydroxide pellets', quantity: 0),
  ],
  apparatus: [apparatusFixture('a1', 'Analytical balance Sartorius Entris II')],
  logs: [
    logFixture('l1', 'c1', 0),
    logFixture('l2', 'c1', 1),
    logFixture('l3', 'c2', 3, amount: 12.5),
    logFixture('l4', 'c1', 9),
  ],
  lastSyncedAt: fixtureNow.subtract(const Duration(minutes: 12)),
  lastUpdated: fixtureNow,
);

final userJson = <String, dynamic>{
  'id': 'u1',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'aisha.rahman-qureshi@university.edu.pk',
  'app_metadata': <String, dynamic>{'provider': 'email'},
  'user_metadata': <String, dynamic>{'name': 'Aisha Rahman-Qureshi'},
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Future<void> pumpScreen(
  WidgetTester tester,
  Widget home, {
  InventoryState? state,
  List<Override> overrides = const [],
  double scale = 1,
  Size size = smallPhone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => SeededInventory(state ?? richState()),
        ),
        isOnlineProvider.overrideWithValue(() async => true),
        ...overrides,
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens a sheet from a button so the sheet gets a real navigator/context.
Widget sheetOpener(
  void Function(BuildContext context, WidgetRef ref) open,
) => Scaffold(
  body: Consumer(
    builder: (context, ref, _) => Center(
      child: FilledButton(
        onPressed: () => open(context, ref),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

