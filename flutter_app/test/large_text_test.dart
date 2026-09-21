import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/home/presentation/dashboard_screen.dart';
import 'package:lab_wizard/features/home/presentation/home_shell.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/reports/presentation/reports_screen.dart';
import 'package:lab_wizard/features/security/app_lock_providers.dart';
import 'package:lab_wizard/features/security/domain/app_lock.dart';
import 'package:lab_wizard/features/security/presentation/lock_screen.dart';
import 'package:lab_wizard/features/sync/domain/sync_conflict.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// A11Y-02: the main screens at Android's largest font scale (200%) on a
/// small phone. Any RenderFlex overflow is reported as a test exception,
/// so a passing run means "nothing is clipped".
const _maxScale = 2.0;
const _smallPhone = Size(360, 740);

class _SeededInventory extends InventoryController {
  _SeededInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> bootstrap(String userId) async {}

  @override
  Future<void> refresh() async {}
}

/// A lock that is already set up and locked, without touching storage.
class _LockedLock extends AppLockController {
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

final _now = DateTime.now();

Chemical _chemical(
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
  expiryDate: _now.add(const Duration(days: 10)),
  hazardClasses: const ['GHS02', 'GHS06', 'GHS07', 'GHS08'],
  barcode: '4006381333931',
);

Apparatus _apparatus(String id, String name) => Apparatus(
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
  warrantyUntil: _now.add(const Duration(days: 20)),
);

ConsumptionLog _log(String id, String itemId, int daysAgo, {double amount = 250}) =>
    ConsumptionLog(
      id: id,
      itemId: itemId,
      itemType: ItemKind.chemical,
      action: InventoryAction.consume,
      amount: amount,
      note: 'Titration practical, second year',
      loggedAt: _now.subtract(Duration(days: daysAgo, hours: 2)),
      createdAt: _now.subtract(Duration(days: daysAgo, hours: 2)),
    );

InventoryState _richState() => InventoryState(
  chemicals: [
    _chemical('c1', 'Hydrochloric acid concentrated (37 %)'),
    _chemical('c2', 'Ethanol', quantity: 80),
    _chemical('c3', 'Sodium hydroxide pellets', quantity: 0),
  ],
  apparatus: [_apparatus('a1', 'Analytical balance Sartorius Entris II')],
  logs: [
    _log('l1', 'c1', 0),
    _log('l2', 'c1', 1),
    _log('l3', 'c2', 3, amount: 12.5),
    _log('l4', 'c1', 9),
  ],
  lastSyncedAt: _now.subtract(const Duration(minutes: 12)),
  lastUpdated: _now,
);

final _userJson = <String, dynamic>{
  'id': 'u1',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'aisha.rahman-qureshi@university.edu.pk',
  'app_metadata': <String, dynamic>{'provider': 'email'},
  'user_metadata': <String, dynamic>{'name': 'Aisha Rahman-Qureshi'},
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Future<void> _pumpLarge(
  WidgetTester tester,
  Widget home, {
  InventoryState? state,
  List<Override> overrides = const [],
  double scale = _maxScale,
  Size size = _smallPhone,
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
          () => _SeededInventory(state ?? _richState()),
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
Widget _opener(
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

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A11Y-02 at 200 % text on a small phone', () {
    testWidgets('chemical shelf, detailed and compact', (tester) async {
      await _pumpLarge(tester, const InventoryScreen(kind: ItemKind.chemical));
      expect(find.text('Ethanol'), findsOneWidget);
      await tester.tap(find.byTooltip('Show compact rows'));
      await tester.pumpAndSettle();
      expect(find.text('Ethanol'), findsOneWidget);
      // Selection mode adds marks and the action bar.
      await tester.longPress(find.text('Ethanol'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsWidgets);
    });

    testWidgets('apparatus shelf with marks', (tester) async {
      await _pumpLarge(tester, const InventoryScreen(kind: ItemKind.apparatus));
      expect(find.textContaining('Analytical balance'), findsOneWidget);
      await tester.tap(find.byTooltip('Show compact rows'));
      await tester.pumpAndSettle();
    });

    testWidgets('item detail sheet', (tester) async {
      await _pumpLarge(
        tester,
        _opener(
          (context, ref) =>
              showItemDetailSheet(context, ref, ItemKind.chemical, 'c1'),
        ),
      );
      await _open(tester);
      expect(find.textContaining('Hydrochloric'), findsWidgets);
    });

    testWidgets('apparatus detail sheet', (tester) async {
      await _pumpLarge(
        tester,
        _opener(
          (context, ref) =>
              showItemDetailSheet(context, ref, ItemKind.apparatus, 'a1'),
        ),
      );
      await _open(tester);
      expect(find.textContaining('Analytical balance'), findsWidgets);
    });

    testWidgets('add and edit forms', (tester) async {
      await _pumpLarge(
        tester,
        _opener(
          (context, ref) => showAddItemSheet(context, ref, ItemKind.chemical),
        ),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('chemical-details-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Add to shelf'), findsOneWidget);
    });

    testWidgets('edit form with every field filled', (tester) async {
      await _pumpLarge(
        tester,
        _opener(
          (context, ref) => showEditItemSheet(
            context,
            ref,
            kind: ItemKind.chemical,
            itemId: 'c1',
          ),
        ),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('chemical-details-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('consume sheet', (tester) async {
      await _pumpLarge(
        tester,
        _opener(
          (context, ref) => showInventoryActionSheet(
            context,
            ref,
            kind: ItemKind.chemical,
            itemId: 'c1',
            action: InventoryAction.consume,
          ),
        ),
      );
      await _open(tester);
      expect(find.text('consume'), findsOneWidget);
    });

    testWidgets('dashboard', (tester) async {
      await _pumpLarge(
        tester,
        DashboardScreen(
          user: User.fromJson(_userJson)!,
          onNavigate: (_) {},
          onSettings: () {},
        ),
      );
      expect(find.textContaining('Aisha'), findsWidgets);
    });

    testWidgets('reports', (tester) async {
      await _pumpLarge(tester, const ReportsScreen());
      expect(find.byKey(const Key('metric-consume')), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-range-month')));
      await tester.pumpAndSettle();
    });

    testWidgets('sync center with conflicts', (tester) async {
      final state = _richState().copyWith(
        outbox: [
          PendingOperation(
            id: 'op-1',
            userId: 'u1',
            type: 'inventory_action',
            payload: const {'item_id': 'c2', 'action': 'consume', 'amount': 90},
            createdAt: _now.subtract(const Duration(minutes: 6)),
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
            createdAt: _now.subtract(const Duration(minutes: 3)),
            label: 'Add chemical Acetone',
          ),
        ],
      );
      await _pumpLarge(tester, const SyncCenterScreen(), state: state);
      expect(find.text('Add chemical Acetone'), findsOneWidget);
    });

    testWidgets('lock screen keypad', (tester) async {
      await _pumpLarge(
        tester,
        const LockScreen(),
        overrides: [appLockProvider.overrideWith(_LockedLock.new)],
      );
      expect(find.byKey(const Key('lock-key-5')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lock-forgot')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock-forgot-confirm')), findsOneWidget);
    });

    testWidgets('bottom navigation', (tester) async {
      await _pumpLarge(
        tester,
        Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: NotebookBottomNavigation(
            selectedIndex: 2,
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('reports'), findsOneWidget);
    });
  });
}
