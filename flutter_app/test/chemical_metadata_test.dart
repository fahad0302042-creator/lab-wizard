import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/core/utils/errors.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/chemical_details.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final added = <(String, ChemicalDetails)>[];
  final updates = <Map<String, dynamic>>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> addChemical({
    required String name,
    required String formula,
    required String unit,
    required double quantity,
    required double threshold,
    required String notes,
    ChemicalDetails details = const ChemicalDetails(),
  }) async {
    added.add((name, details));
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

Chemical _chemical(
  String id,
  String name, {
  DateTime? expiry,
  List<String> hazards = const [],
  String? supplier,
  String? casNumber,
}) => Chemical(
  id: id,
  name: name,
  formula: 'F',
  unit: 'mL',
  quantity: 100,
  initialQuantity: 100,
  lowStockThreshold: 10,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  expiryDate: expiry,
  hazardClasses: hazards,
  supplier: supplier,
  casNumber: casNumber,
);

Future<_FakeInventory> _pumpWithSheet(
  WidgetTester tester, {
  required List<Chemical> chemicals,
  required void Function(BuildContext context, WidgetRef ref) open,
}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => fake = _FakeInventory(InventoryState(chemicals: chemicals)),
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
  group('DATA-01 model', () {
    test('old rows without metadata stay valid and round-trip unchanged', () {
      final chemical = Chemical.fromMap({
        'id': 'c1',
        'name': 'Water',
        'formula': 'H2O',
        'unit': 'mL',
        'quantity': 10,
        'initial_quantity': 10,
        'low_stock_threshold': 1,
        'notes': '',
        'qr_code': 'qr',
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(chemical.hasMetadata, isFalse);
      expect(chemical.expiryState(), ExpiryState.none);
      expect(chemical.hazards, isEmpty);
      for (final column in chemicalMetadataColumns) {
        expect(chemical.toMap().containsKey(column), isFalse, reason: column);
      }
    });

    test('metadata columns parse from server and cache shapes', () {
      final fromServer = Chemical.fromMap({
        'id': 'c1',
        'name': 'Ethanol',
        'supplier': ' Merck ',
        'cas_number': '64-17-5',
        'concentration': '96%',
        'location': 'Cabinet B',
        'expiry_date': '2027-03-01',
        'hazard_classes': ['GHS02', 'ghs07', 'bogus', 'GHS02'],
      });
      expect(fromServer.supplier, 'Merck');
      expect(fromServer.expiryDate, DateTime(2027, 3, 1));
      expect(fromServer.hazardClasses, ['GHS02', 'GHS07']);
      expect(fromServer.hasMetadata, isTrue);
      expect(fromServer.toMap()['expiry_date'], '2027-03-01');
      expect(fromServer.toMap()['hazard_classes'], ['GHS02', 'GHS07']);

      final fromLiteral = Chemical.fromMap({
        'id': 'c2',
        'name': 'Acid',
        'hazard_classes': '{GHS05,GHS07}',
        'expiry_date': '2027-03-01T00:00:00+00:00',
      });
      expect(fromLiteral.hazardClasses, ['GHS05', 'GHS07']);
      expect(fromLiteral.expiryDate, DateTime(2027, 3, 1));
      expect(parseHazardList('GHS02; GHS09'), ['GHS02', 'GHS09']);
      expect(parseHazardList(''), isEmpty);
    });

    test('CAS numbers are checked with their check digit', () {
      expect(isValidCasNumber('7732-18-5'), isTrue);
      expect(isValidCasNumber('64-17-5'), isTrue);
      expect(isValidCasNumber(' 50-00-0 '), isTrue);
      expect(isValidCasNumber('7732-18-4'), isFalse);
      expect(isValidCasNumber('7732185'), isFalse);
      expect(isValidCasNumber('abc'), isFalse);
    });

    test('expiry state uses a 30 day warning window on calendar days', () {
      final now = DateTime(2026, 9, 21, 15, 30);
      expect(expiryStateFor(null, now: now), ExpiryState.none);
      expect(
        expiryStateFor(DateTime(2026, 9, 20), now: now),
        ExpiryState.expired,
      );
      expect(
        expiryStateFor(DateTime(2026, 9, 21), now: now),
        ExpiryState.expiringSoon,
      );
      expect(
        expiryStateFor(DateTime(2026, 10, 21), now: now),
        ExpiryState.expiringSoon,
      );
      expect(expiryStateFor(DateTime(2026, 10, 22), now: now), ExpiryState.ok);
      expect(expiryCaption(DateTime(2026, 9, 21), now: now), 'expires today');
      expect(
        expiryCaption(DateTime(2026, 9, 18), now: now),
        'expired 3 days ago',
      );
      expect(
        expiryCaption(DateTime(2026, 10, 3), now: now),
        'expires in 12 days',
      );
    });

    test('details compare by content and produce full column maps', () {
      const a = ChemicalDetails(
        supplier: 'Merck',
        hazardClasses: ['GHS02', 'GHS07'],
      );
      const b = ChemicalDetails(
        supplier: 'Merck ',
        hazardClasses: ['ghs02', 'GHS07'],
      );
      const c = ChemicalDetails(supplier: 'Merck', hazardClasses: ['GHS02']);
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(c), isFalse);
      expect(const ChemicalDetails().isEmpty, isTrue);
      expect(const ChemicalDetails(location: ' ').isEmpty, isTrue);
      final changes = c.toChanges();
      expect(changes['supplier'], 'Merck');
      expect(changes['cas_number'], isNull);
      expect(changes['expiry_date'], isNull);
      expect(changes['hazard_classes'], ['GHS02']);
      expect(changes.keys.toSet(), chemicalMetadataColumns);
    });

    test('a missing column on the server becomes a migration hint', () {
      final message = friendlyErrorMessage(
        StateError(
          "Could not find the 'supplier' column of 'chemicals' in the "
          'schema cache',
        ),
      );
      expect(message, contains('flutter_app/supabase'));
      expect(
        friendlyErrorMessage(StateError('Only 5 available.')),
        'Only 5 available.',
      );
    });
  });

  group('DATA-01 forms', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('add form validates CAS and passes details through', (
      tester,
    ) async {
      final fake = await _pumpWithSheet(
        tester,
        chemicals: const [],
        open: (context, ref) =>
            showAddItemSheet(context, ref, ItemKind.chemical),
      );
      await tester.enterText(find.byType(TextFormField).first, 'Ethanol');
      await tester.enterText(find.byType(TextFormField).at(2), '100');
      await tester.ensureVisible(
        find.byKey(const Key('chemical-details-toggle')),
      );
      await tester.tap(find.byKey(const Key('chemical-details-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-cas')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('detail-cas')));
      await tester.enterText(find.byKey(const Key('detail-cas')), '64-17-6');
      await tester.ensureVisible(find.text('Add to shelf'));
      await tester.tap(find.text('Add to shelf'));
      await tester.pumpAndSettle();
      expect(fake.added, isEmpty);
      expect(find.textContaining('Not a valid CAS number'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('detail-cas')));
      await tester.enterText(find.byKey(const Key('detail-cas')), '64-17-5');
      await tester.enterText(find.byKey(const Key('detail-supplier')), 'Merck');
      await tester.enterText(
        find.byKey(const Key('detail-expiry')),
        '2030-01-31',
      );
      await tester.ensureVisible(find.byKey(const Key('hazard-GHS02')));
      await tester.tap(find.byKey(const Key('hazard-GHS02')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add to shelf'));
      await tester.tap(find.text('Add to shelf'));
      await tester.pumpAndSettle();

      expect(fake.added, hasLength(1));
      final (name, details) = fake.added.single;
      expect(name, 'Ethanol');
      expect(details.supplier, 'Merck');
      expect(details.casNumber, '64-17-5');
      expect(details.expiryDate, DateTime(2030, 1, 31));
      expect(details.hazardClasses, ['GHS02']);
    });

    testWidgets('edit form only sends metadata columns when they changed', (
      tester,
    ) async {
      final chemical = _chemical('c1', 'Acetone', supplier: 'Merck');
      final fake = await _pumpWithSheet(
        tester,
        chemicals: [chemical],
        open: (context, ref) => showEditItemSheet(
          context,
          ref,
          kind: ItemKind.chemical,
          itemId: 'c1',
        ),
      );
      // Untouched details: the update must not mention metadata columns.
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(fake.updates, hasLength(1));
      expect(fake.updates.single.containsKey('supplier'), isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Existing metadata keeps the section open.
      expect(find.byKey(const Key('detail-supplier')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('detail-location')));
      await tester.enterText(
        find.byKey(const Key('detail-location')),
        'Cabinet B',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(fake.updates, hasLength(2));
      expect(fake.updates.last['supplier'], 'Merck');
      expect(fake.updates.last['location'], 'Cabinet B');
      expect(fake.updates.last['expiry_date'], isNull);
    });
  });

  group('DATA-02 presentation', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('item detail shows metadata, expiry copy and hazards', (
      tester,
    ) async {
      final chemical = _chemical(
        'c1',
        'Ethanol',
        supplier: 'Merck',
        casNumber: '64-17-5',
        expiry: _today().add(const Duration(days: 10)),
        hazards: const ['GHS02', 'GHS07'],
      );
      await _pumpWithSheet(
        tester,
        chemicals: [chemical],
        open: (context, ref) =>
            showItemDetailSheet(context, ref, ItemKind.chemical, 'c1'),
      );
      await tester.ensureVisible(
        find.byKey(const Key('chemical-details-summary')),
      );
      expect(find.text('Merck'), findsOneWidget);
      expect(find.text('64-17-5'), findsOneWidget);
      expect(find.textContaining('expires in 10 days'), findsOneWidget);
      expect(find.byKey(const Key('detail-hazard-GHS02')), findsOneWidget);
      expect(find.byKey(const Key('detail-hazard-GHS07')), findsOneWidget);
    });

    testWidgets('shelf marks expiring chemicals and can filter to them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chemicals = [
        _chemical(
          'c1',
          'Old acid',
          expiry: _today().subtract(const Duration(days: 2)),
          hazards: const ['GHS05'],
        ),
        _chemical(
          'c2',
          'Soon solvent',
          expiry: _today().add(const Duration(days: 5)),
        ),
        _chemical('c3', 'Fresh salt'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(InventoryState(chemicals: chemicals)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(kind: ItemKind.chemical),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpiryBadge), findsNWidgets(2));
      expect(find.text('expired'), findsOneWidget);
      expect(find.byType(HazardStrip), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-expiring')));
      await tester.pumpAndSettle();
      expect(find.text('Old acid'), findsOneWidget);
      expect(find.text('Soon solvent'), findsOneWidget);
      expect(find.text('Fresh salt'), findsNothing);
    });
  });
}
