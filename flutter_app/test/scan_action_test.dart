import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/scanner/presentation/scan_action_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 9, 21, 10);

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final actions = <(String, InventoryAction, double, String)>[];
  final returns = <(String, double)>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}

  @override
  Future<ConsumptionLog> applyAction({
    required String itemId,
    required ItemKind itemType,
    required InventoryAction action,
    required double amount,
    required String note,
    required DateTime date,
  }) async {
    final current = itemType == ItemKind.chemical
        ? state.chemicals.firstWhere((item) => item.id == itemId).quantity
        : state.apparatus.firstWhere((item) => item.id == itemId).quantity;
    if (action != InventoryAction.restock && amount > current) {
      throw StateError('Only ${formatQuantity(current)} available.');
    }
    actions.add((itemId, action, amount, note));
    final next = action == InventoryAction.restock
        ? current + amount
        : current - amount;
    state = state.copyWith(
      chemicals: [
        for (final item in state.chemicals)
          item.id == itemId ? item.copyWith(quantity: next) : item,
      ],
      apparatus: [
        for (final item in state.apparatus)
          item.id == itemId ? item.copyWith(quantity: next) : item,
      ],
    );
    return ConsumptionLog(
      id: 'log-${actions.length}',
      itemId: itemId,
      itemType: itemType,
      action: action,
      amount: amount,
      note: note,
      loggedAt: date,
      createdAt: date,
    );
  }

  @override
  Future<ApparatusCheckout> returnApparatus({
    required String checkoutId,
    required double quantity,
    required String note,
  }) async {
    final loan = state.checkouts.firstWhere((entry) => entry.id == checkoutId);
    if (quantity > loan.outstanding) {
      throw StateError(
        'Only ${formatQuantity(loan.outstanding)} still out on this loan.',
      );
    }
    returns.add((checkoutId, quantity));
    final updated = loan.copyWith(
      returnedQuantity: loan.returnedQuantity + quantity,
      returnedAt: loan.outstanding - quantity <= 0 ? _now : null,
    );
    state = state.copyWith(
      checkouts: [
        for (final entry in state.checkouts)
          entry.id == checkoutId ? updated : entry,
      ],
      apparatus: [
        for (final item in state.apparatus)
          item.id == loan.apparatusId
              ? item.copyWith(quantity: item.quantity + quantity)
              : item,
      ],
    );
    return updated;
  }
}

final _acetone = Chemical(
  id: 'c1',
  name: 'Acetone',
  formula: 'C3H6O',
  unit: 'mL',
  quantity: 50,
  initialQuantity: 100,
  lowStockThreshold: 10,
  notes: '',
  qrCode: 'code-1',
  createdAt: DateTime(2026, 1, 1),
);

final _beaker = Apparatus(
  id: 'a1',
  name: 'Beaker 250 mL',
  category: 'glassware',
  quantity: 9,
  initialQuantity: 12,
  lowStockThreshold: 2,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  serialNumber: 'SN-7',
);

ApparatusCheckout _loan(String id, String person, double quantity) =>
    ApparatusCheckout(
      id: id,
      apparatusId: 'a1',
      quantity: quantity,
      person: person,
      checkedOutAt: _now.subtract(const Duration(days: 1)),
    );

Future<_FakeInventory> _pump(
  WidgetTester tester, {
  required InventoryState seed,
  required ItemKind kind,
  required String itemId,
  required List<ScanActionResult?> results,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(() => fake = _FakeInventory(seed)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  results.add(
                    await showScanActionSheet(
                      context,
                      kind: kind,
                      itemId: itemId,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('confirmation lines read naturally', () {
    expect(
      scanActionMessage(
        action: InventoryAction.consume,
        name: 'Acetone',
        amount: 5,
        unit: 'mL',
        after: 45,
      ),
      'Used 5 mL of Acetone · 45 mL left',
    );
    expect(
      scanActionMessage(
        action: InventoryAction.restock,
        name: 'Beaker',
        amount: 2,
        unit: 'pcs',
        after: 11,
      ),
      'Restocked 2 pcs of Beaker · now 11 pcs',
    );
    expect(quickAmountsFor(ItemKind.chemical), [1, 5, 10, 25, 50]);
    expect(quickAmountsFor(ItemKind.apparatus), [1, 2, 5, 10]);
  });

  testWidgets('a chemical can be used with a quick amount and undone', (
    tester,
  ) async {
    final results = <ScanActionResult?>[];
    final fake = await _pump(
      tester,
      seed: InventoryState(chemicals: [_acetone]),
      kind: ItemKind.chemical,
      itemId: 'c1',
      results: results,
    );
    expect(find.text('Acetone'), findsOneWidget);
    expect(find.text('50 mL in stock'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('scan-amount'))).controller!.text, isEmpty);

    await tester.tap(find.byKey(const Key('scan-use')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
    expect(fake.actions, isEmpty);

    await tester.tap(find.byKey(const Key('scan-chip-5')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero.'), findsNothing);
    await tester.tap(find.byKey(const Key('scan-use')));
    await tester.pumpAndSettle();

    expect(fake.actions, [('c1', InventoryAction.consume, 5.0, 'via scanner')]);
    expect(results.single?.message, 'Used 5 mL of Acetone · 45 mL left');
    expect(results.single?.openDetails, isFalse);
    expect(find.byKey(const Key('scan-use')), findsNothing);
    expect(find.text('Used 5 mL of Acetone · 45 mL left'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    // FORM-01: the amount is remembered for the next scan.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('scan-amount'))).controller!.text, '5');
  });

  testWidgets('stock errors stay inline and the sheet remains open', (
    tester,
  ) async {
    final results = <ScanActionResult?>[];
    final fake = await _pump(
      tester,
      seed: InventoryState(chemicals: [_acetone]),
      kind: ItemKind.chemical,
      itemId: 'c1',
      results: results,
    );
    await tester.enterText(find.byKey(const Key('scan-amount')), '500');
    await tester.tap(find.byKey(const Key('scan-damage')));
    await tester.pumpAndSettle();
    expect(find.text('Only 50 available.'), findsOneWidget);
    expect(fake.actions, isEmpty);
    expect(results, isEmpty);
    expect(find.byKey(const Key('scan-damage')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-details')));
    await tester.pumpAndSettle();
    expect(results.single?.openDetails, isTrue);
    expect(results.single?.message, isNull);
  });

  testWidgets('apparatus offers a return that picks the loan', (tester) async {
    final results = <ScanActionResult?>[];
    final fake = await _pump(
      tester,
      seed: InventoryState(
        apparatus: [_beaker],
        checkouts: [_loan('l1', 'Ali', 2), _loan('l2', 'Sara', 1)],
      ),
      kind: ItemKind.apparatus,
      itemId: 'a1',
      results: results,
    );
    expect(find.text('glassware · S/N SN-7'), findsOneWidget);
    expect(find.text('9 pcs in stock · 3 on loan'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('scan-amount'))).controller!.text, '1');
    expect(find.text('Return (3 out)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-return')));
    await tester.pumpAndSettle();
    expect(find.text('Which loan is coming back?'), findsOneWidget);
    expect(find.text('Ali · 2 out'), findsOneWidget);
    expect(find.text('Sara · 1 out'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-loan-l2')));
    await tester.pumpAndSettle();

    expect(fake.returns, [('l2', 1.0)]);
    expect(
      results.single?.message,
      'Returned 1 of Beaker 250 mL · 10 pcs in stock',
    );
  });

  testWidgets('a single open loan is returned without asking', (
    tester,
  ) async {
    final results = <ScanActionResult?>[];
    final fake = await _pump(
      tester,
      seed: InventoryState(
        apparatus: [_beaker],
        checkouts: [_loan('l1', 'Ali', 2)],
      ),
      kind: ItemKind.apparatus,
      itemId: 'a1',
      results: results,
    );
    await tester.enterText(find.byKey(const Key('scan-amount')), '3');
    await tester.tap(find.byKey(const Key('scan-return')));
    await tester.pumpAndSettle();
    expect(find.text('Only 2 still out on this loan.'), findsOneWidget);
    expect(fake.returns, isEmpty);

    await tester.tap(find.byKey(const Key('scan-chip-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-return')));
    await tester.pumpAndSettle();
    expect(fake.returns, [('l1', 2.0)]);
    expect(results.single?.message, startsWith('Returned 2 of Beaker 250 mL'));
  });
}
