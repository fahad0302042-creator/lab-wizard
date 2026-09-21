import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/duplicates.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final added = <(String, String, String, double)>[];
  final actions = <(InventoryAction, double)>[];

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
    added.add((name, formula, unit, threshold));
  }

  @override
  Future<ConsumptionLog> applyAction({
    required String itemId,
    required ItemKind itemType,
    required InventoryAction action,
    required double amount,
    required String note,
    required DateTime date,
  }) async {
    actions.add((action, amount));
    return ConsumptionLog(
      id: 'log',
      itemId: itemId,
      itemType: itemType,
      action: action,
      amount: amount,
      note: note,
      loggedAt: date,
      createdAt: date,
    );
  }
}

final _acetone = Chemical(
  id: 'chem-acetone',
  name: 'Acetone',
  formula: 'C3H6O',
  unit: 'mL',
  quantity: 400,
  initialQuantity: 500,
  lowStockThreshold: 50,
  notes: '',
  qrCode: 'qr-acetone',
  createdAt: DateTime(2026, 1, 1),
);

Future<_FakeInventory> _pumpWithSheet(
  WidgetTester tester, {
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
          () => fake = _FakeInventory(InventoryState(chemicals: [_acetone])),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Warm the memory provider up the way the shelf does.
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
  group('DUP-01 matching', () {
    test('names are compared without case, spacing or punctuation', () {
      expect(normalizeName('  Sodium  Chloride. '), 'sodium chloride');
      expect(normalizeName('sodium-chloride'), 'sodium chloride');
      expect(normalizeFormula('CuSO4 · 5H2O'), 'cuso45h2o');
      expect(normalizeFormula('cuso4.5h2o'), 'cuso45h2o');
    });

    test('chemicals match on normalized name or formula', () {
      final matches = findChemicalDuplicates(
        existing: [_acetone],
        name: 'acetone ',
        formula: '',
      );
      expect(matches.single.reason, 'same name');
      expect(matches.single.detail, 'C3H6O · 400 mL');

      final byFormula = findChemicalDuplicates(
        existing: [_acetone],
        name: 'Propanone',
        formula: 'c3h6o',
      );
      expect(byFormula.single.reason, 'same formula');

      expect(
        findChemicalDuplicates(
          existing: [_acetone],
          name: 'Ethanol',
          formula: '',
        ),
        isEmpty,
      );
      expect(
        findChemicalDuplicates(
          existing: [_acetone],
          name: 'Acetone',
          formula: '',
          excludeId: _acetone.id,
        ),
        isEmpty,
      );
    });

    test('apparatus matches on name and reports the category', () {
      final beaker = Apparatus(
        id: 'a1',
        name: 'Beaker 250 mL',
        category: 'glassware',
        quantity: 10,
        initialQuantity: 10,
        lowStockThreshold: 2,
        notes: '',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(
        findApparatusDuplicates(
          existing: [beaker],
          name: 'beaker 250 ml',
          category: 'glassware',
        ).single.reason,
        'same name and category',
      );
      expect(
        findApparatusDuplicates(
          existing: [beaker],
          name: 'Beaker 250 mL',
          category: 'other',
        ).single.reason,
        'same name in glassware',
      );
    });
  });

  group('DUP-01 add form', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('warns about an existing item and allows adding anyway', (
      tester,
    ) async {
      final fake = await _pumpWithSheet(
        tester,
        open: (context, ref) =>
            showAddItemSheet(context, ref, ItemKind.chemical),
      );
      await tester.enterText(find.byType(TextFormField).first, 'acetone');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duplicate-warning')), findsOneWidget);
      expect(find.text('Acetone'), findsOneWidget);
      expect(find.textContaining('same name'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(2), '100');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add to shelf'));
      await tester.tap(find.text('Add to shelf'));
      await tester.pumpAndSettle();
      expect(fake.added, isEmpty);
      expect(find.textContaining('looks like a duplicate'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('duplicate-add-anyway')));
      await tester.tap(find.byKey(const Key('duplicate-add-anyway')));
      await tester.pumpAndSettle();
      expect(fake.added.single.$1, 'acetone');
      expect(find.byKey(const Key('duplicate-warning')), findsNothing);
    });
  });

  group('FORM-01 form memory', () {
    testWidgets('add form starts from the remembered unit and threshold', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'form.anonymous.unit': 'g',
        'form.anonymous.threshold.chemical': 25.0,
      });
      final fake = await _pumpWithSheet(
        tester,
        open: (context, ref) =>
            showAddItemSheet(context, ref, ItemKind.chemical),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'g',
      );
      expect(find.text('25'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Ethanol');
      await tester.enterText(find.byType(TextFormField).at(2), '100');
      await tester.enterText(find.byType(TextFormField).at(3), '30');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add to shelf'));
      await tester.tap(find.text('Add to shelf'));
      await tester.pumpAndSettle();
      expect(fake.added.single, ('Ethanol', '', 'g', 30.0));

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getDouble('form.anonymous.threshold.chemical'), 30.0);
      expect(preferences.getString('form.anonymous.unit'), 'g');
    });

    testWidgets('action form remembers the last amount per action', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'form.anonymous.amount.chemical.consume': 12.5,
      });
      final fake = await _pumpWithSheet(
        tester,
        open: (context, ref) => showInventoryActionSheet(
          context,
          ref,
          kind: ItemKind.chemical,
          itemId: _acetone.id,
          action: InventoryAction.consume,
        ),
      );
      expect(find.text('12.5'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm consume'));
      await tester.pumpAndSettle();
      expect(fake.actions, [(InventoryAction.consume, 20.0)]);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getDouble('form.anonymous.amount.chemical.consume'),
        20.0,
      );
    });

    testWidgets('prefill can be switched off and values forgotten', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'form.anonymous.threshold.chemical': 25.0,
        'form.anonymous.prefill_threshold': false,
      });
      await _pumpWithSheet(
        tester,
        open: (context, ref) =>
            showAddItemSheet(context, ref, ItemKind.chemical),
      );
      expect(find.text('25'), findsNothing);
    });
  });
}
