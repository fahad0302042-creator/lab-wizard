import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final added = <(String, String, ApparatusDetails)>[];
  final updates = <Map<String, dynamic>>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> addApparatus({
    required String name,
    required String category,
    required double quantity,
    required double threshold,
    required String notes,
    ApparatusDetails details = const ApparatusDetails(),
  }) async {
    added.add((name, category, details));
  }

  @override
  Future<void> updateItem({
    required ItemKind type,
    required String id,
    required Map<String, dynamic> changes,
    bool force = false,
  }) async {
    updates.add(changes);
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Apparatus _gear(
  String id,
  String name, {
  String? serial,
  String? condition,
  String? assignedTo,
  DateTime? warranty,
}) => Apparatus(
  id: id,
  name: name,
  category: 'glassware',
  quantity: 4,
  initialQuantity: 4,
  lowStockThreshold: 1,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  serialNumber: serial,
  condition: condition,
  assignedTo: assignedTo,
  warrantyUntil: warranty,
);

Future<_FakeInventory> _pumpWithSheet(
  WidgetTester tester, {
  required List<Apparatus> apparatus,
  required void Function(BuildContext context, WidgetRef ref) open,
}) async {
  tester.view.physicalSize = const Size(420, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => fake = _FakeInventory(InventoryState(apparatus: apparatus)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(formMemoryProvider);
              return Center(
                child: FilledButton(
                  onPressed: () => open(context, ref),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('GEAR-01 model', () {
    test('old rows stay valid and metadata round-trips', () {
      final plain = Apparatus.fromMap({
        'id': 'a1',
        'name': 'Beaker',
        'category': 'glassware',
        'quantity': 3,
      });
      expect(plain.hasMetadata, isFalse);
      for (final column in apparatusMetadataColumns) {
        expect(plain.toMap().containsKey(column), isFalse, reason: column);
      }

      final rich = Apparatus.fromMap({
        'id': 'a2',
        'name': 'Balance',
        'serial_number': ' SN-42 ',
        'condition': 'Needs Repair',
        'assigned_to': 'Aisha',
        'location': 'Bench 3',
        'purchase_date': '2024-05-01',
        'warranty_until': '2026-05-01T00:00:00+00:00',
      });
      expect(rich.serialNumber, 'SN-42');
      expect(rich.conditionValue, ApparatusCondition.needsRepair);
      expect(rich.purchaseDate, DateTime(2024, 5, 1));
      expect(rich.warrantyUntil, DateTime(2026, 5, 1));
      expect(rich.toMap()['warranty_until'], '2026-05-01');
      expect(rich.toMap()['condition'], 'Needs Repair');
    });

    test('details compare by content and lower-case the condition', () {
      const a = ApparatusDetails(serialNumber: 'X1', condition: 'Fair');
      const b = ApparatusDetails(serialNumber: 'X1 ', condition: 'fair');
      const c = ApparatusDetails(serialNumber: 'X2', condition: 'fair');
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(c), isFalse);
      expect(const ApparatusDetails(assignedTo: ' ').isEmpty, isTrue);
      final changes = a.toChanges();
      expect(changes.keys.toSet(), apparatusMetadataColumns);
      expect(changes['condition'], 'fair');
      expect(changes['warranty_until'], isNull);
      expect(
        ApparatusCondition.fromLabel('needsRepair'),
        ApparatusCondition.needsRepair,
      );
      expect(ApparatusCondition.fromLabel('broken'), isNull);
    });
  });

  group('GEAR-01 forms', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('add form captures serial, condition and warranty', (
      tester,
    ) async {
      final fake = await _pumpWithSheet(
        tester,
        apparatus: const [],
        open: (context, ref) =>
            showAddItemSheet(context, ref, ItemKind.apparatus),
      );
      await tester.enterText(find.byType(TextFormField).first, 'Hot plate');
      await tester.enterText(find.byType(TextFormField).at(1), '2');
      await tester.ensureVisible(
        find.byKey(const Key('apparatus-details-toggle')),
      );
      await tester.tap(find.byKey(const Key('apparatus-details-toggle')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('gear-serial')), 'HP-7');
      await tester.ensureVisible(find.byKey(const Key('gear-condition')));
      await tester.tap(find.byKey(const Key('gear-condition')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('needs repair').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('gear-warranty')),
        '2020-13-01',
      );
      await tester.ensureVisible(find.text('Add to shelf'));
      await tester.tap(find.text('Add to shelf'));
      await tester.pumpAndSettle();
      expect(fake.added, isEmpty);
      expect(find.text('Use the YYYY-MM-DD format'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('gear-warranty')),
        '2020-01-31',
      );
      await tester.ensureVisible(find.text('Add to shelf'));
      await tester.tap(find.text('Add to shelf'));
      await tester.pumpAndSettle();
      expect(fake.added, hasLength(1));
      final (name, category, details) = fake.added.single;
      expect(name, 'Hot plate');
      expect(category, 'glassware');
      expect(details.serialNumber, 'HP-7');
      expect(details.condition, 'needs repair');
      expect(details.warrantyUntil, DateTime(2020, 1, 31));
    });

    testWidgets('edit form sends metadata only when it changed', (
      tester,
    ) async {
      final item = _gear('a1', 'Balance', serial: 'SN-1', condition: 'good');
      final fake = await _pumpWithSheet(
        tester,
        apparatus: [item],
        open: (context, ref) => showEditItemSheet(
          context,
          ref,
          kind: ItemKind.apparatus,
          itemId: 'a1',
        ),
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(fake.updates.single.containsKey('serial_number'), isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gear-assigned')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('gear-assigned')), 'Bilal');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(fake.updates, hasLength(2));
      expect(fake.updates.last['serial_number'], 'SN-1');
      expect(fake.updates.last['assigned_to'], 'Bilal');
      expect(fake.updates.last['condition'], 'good');
      expect(fake.updates.last['purchase_date'], isNull);
    });
  });

  group('GEAR-01 presentation', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('item sheet lists the metadata with warranty copy', (
      tester,
    ) async {
      final item = _gear(
        'a1',
        'Balance',
        serial: 'SN-1',
        condition: 'needs repair',
        assignedTo: 'Aisha',
        warranty: _today().subtract(const Duration(days: 3)),
      );
      await _pumpWithSheet(
        tester,
        apparatus: [item],
        open: (context, ref) =>
            showItemDetailSheet(context, ref, ItemKind.apparatus, 'a1'),
      );
      await tester.ensureVisible(
        find.byKey(const Key('apparatus-details-summary')),
      );
      expect(find.text('SN-1'), findsOneWidget);
      expect(find.text('needs repair'), findsOneWidget);
      expect(find.text('Aisha'), findsOneWidget);
      expect(find.textContaining('ended 3 days ago'), findsOneWidget);
    });

    testWidgets('shelf rows flag condition, assignee and warranty', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = [
        _gear('a1', 'Balance', condition: 'needs repair'),
        _gear('a2', 'Burette', assignedTo: 'Bilal'),
        _gear(
          'a3',
          'Centrifuge',
          condition: 'good',
          warranty: _today().add(const Duration(days: 10)),
        ),
        _gear('a4', 'Dish'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(InventoryState(apparatus: items)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(kind: ItemKind.apparatus),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mark-condition')), findsOneWidget);
      expect(find.byKey(const Key('mark-assigned')), findsOneWidget);
      expect(find.byKey(const Key('mark-warranty')), findsOneWidget);
      expect(find.text('warranty ending'), findsOneWidget);
    });
  });
}
