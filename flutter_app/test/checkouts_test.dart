import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/data/inventory_repository.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/checkout_sheets.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed, {this.failWith});

  final InventoryState seed;
  final Object? failWith;
  final checkouts = <(String, double, String, String, DateTime?)>[];
  final returns = <(String, double, String)>[];

  @override
  InventoryState build() => seed;

  @override
  Future<ApparatusCheckout> checkoutApparatus({
    required String apparatusId,
    required double quantity,
    required String person,
    required String note,
    DateTime? dueAt,
  }) async {
    if (failWith != null) throw failWith!;
    checkouts.add((apparatusId, quantity, person, note, dueAt));
    final checkout = ApparatusCheckout(
      id: 'new-${checkouts.length}',
      apparatusId: apparatusId,
      quantity: quantity,
      person: person.trim(),
      note: note.trim(),
      checkedOutAt: DateTime.now(),
      dueAt: dueAt,
    );
    state = state.copyWith(checkouts: [checkout, ...state.checkouts]);
    return checkout;
  }

  @override
  Future<ApparatusCheckout> returnApparatus({
    required String checkoutId,
    required double quantity,
    required String note,
  }) async {
    returns.add((checkoutId, quantity, note));
    final current = state.checkouts.firstWhere(
      (entry) => entry.id == checkoutId,
    );
    final returned = current.returnedQuantity + quantity;
    final updated = current.copyWith(
      returnedQuantity: returned,
      returnedAt: returned >= current.quantity ? DateTime.now() : null,
      returnNote: note,
    );
    state = state.copyWith(
      checkouts: state.checkouts
          .map((entry) => entry.id == checkoutId ? updated : entry)
          .toList(),
    );
    return updated;
  }
}

Apparatus _gear(String id, String name, {double quantity = 4}) => Apparatus(
  id: id,
  name: name,
  category: 'glassware',
  quantity: quantity,
  initialQuantity: quantity,
  lowStockThreshold: 1,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
);

ApparatusCheckout _loan(
  String id,
  String apparatusId, {
  double quantity = 1,
  double returned = 0,
  String person = 'Aisha',
  DateTime? due,
  DateTime? returnedAt,
  Duration age = const Duration(hours: 2),
}) => ApparatusCheckout(
  id: id,
  apparatusId: apparatusId,
  quantity: quantity,
  returnedQuantity: returned,
  person: person,
  checkedOutAt: DateTime.now().subtract(age),
  dueAt: due,
  returnedAt: returnedAt,
);

Future<_FakeInventory> _pump(
  WidgetTester tester, {
  required InventoryState seed,
  required void Function(BuildContext context, WidgetRef ref) open,
  Object? failWith,
}) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => fake = _FakeInventory(seed, failWith: failWith),
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
  group('GEAR-02 state', () {
    test('availability subtracts open loans only', () {
      final item = _gear('a1', 'Beaker', quantity: 5);
      final state = InventoryState(
        apparatus: [item],
        checkouts: [
          _loan('c1', 'a1', quantity: 2),
          _loan('c2', 'a1', quantity: 2, returned: 1),
          _loan('c3', 'a1', quantity: 3, returnedAt: DateTime(2026, 9, 1)),
          _loan('c4', 'other', quantity: 9),
        ],
      );
      expect(state.openCheckoutsFor('a1').map((c) => c.id), ['c1', 'c2']);
      expect(state.checkedOutCount('a1'), 3);
      expect(state.availableCount(item), 2);
      // Stock adjusted below the lent amount never goes negative.
      expect(state.availableCount(_gear('a1', 'Beaker', quantity: 1)), 0);
      expect(state.overdueCheckouts(), isEmpty);
    });

    test('overdue loans are open loans past their due date', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final state = InventoryState(
        checkouts: [
          _loan('late', 'a1', due: past),
          _loan('back', 'a1', due: past, returnedAt: DateTime.now()),
          _loan('fine', 'a1', due: DateTime.now().add(const Duration(days: 3))),
        ],
      );
      expect(state.overdueCheckouts().map((c) => c.id), ['late']);
      expect(dueCaption(past), 'overdue by 2 days');
      expect(dueCaption(DateTime.now()), 'due today');
      expect(
        dueCaption(DateTime.now().add(const Duration(days: 1))),
        'due tomorrow',
      );
      expect(dueCaption(null), '');
    });
  });

  group('GEAR-02 sheets', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('item sheet shows availability, open loans and returns', (
      tester,
    ) async {
      final item = _gear('a1', 'Balance', quantity: 4);
      final due = DateTime.now().subtract(const Duration(days: 1));
      await _pump(
        tester,
        seed: InventoryState(
          apparatus: [item],
          checkouts: [
            _loan('c1', 'a1', quantity: 2, person: 'Aisha', due: due),
            _loan(
              'c2',
              'a1',
              person: 'Bilal',
              returnedAt: DateTime.now(),
              age: const Duration(days: 3),
            ),
          ],
        ),
        open: (context, ref) =>
            showItemDetailSheet(context, ref, ItemKind.apparatus, 'a1'),
      );
      await tester.ensureVisible(find.byKey(const Key('checkout-open')));
      expect(find.text('2 of 4 available · 2 checked out'), findsOneWidget);
      expect(find.byKey(const Key('checkout-c1')), findsOneWidget);
      expect(find.textContaining('overdue by 1 day'), findsOneWidget);
      expect(find.byKey(const Key('return-c1')), findsOneWidget);
      expect(find.byKey(const Key('checkout-past-c2')), findsOneWidget);
      expect(find.byKey(const Key('return-c2')), findsNothing);
    });

    testWidgets('check out button is disabled when nothing is available', (
      tester,
    ) async {
      await _pump(
        tester,
        seed: InventoryState(
          apparatus: [_gear('a1', 'Balance', quantity: 1)],
          checkouts: [_loan('c1', 'a1')],
        ),
        open: (context, ref) =>
            showItemDetailSheet(context, ref, ItemKind.apparatus, 'a1'),
      );
      await tester.ensureVisible(find.byKey(const Key('checkout-open')));
      final button = tester.widget<TextButton>(
        find.byKey(const Key('checkout-open')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('0 of 1 available · 1 checked out'), findsOneWidget);
    });

    testWidgets('checkout form validates and submits a loan', (tester) async {
      final fake = await _pump(
        tester,
        seed: InventoryState(
          apparatus: [_gear('a1', 'Balance', quantity: 3)],
          checkouts: [_loan('c1', 'a1', person: 'Aisha')],
        ),
        open: (context, ref) => showCheckoutSheet(context, 'a1'),
      );
      expect(find.text('2 of 3 available'), findsOneWidget);
      expect(find.byKey(const Key('checkout-person-Aisha')), findsOneWidget);

      // Empty person and too many pieces are rejected before saving.
      await tester.enterText(find.byKey(const Key('checkout-quantity')), '5');
      await tester.tap(find.byKey(const Key('checkout-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Only 2 available'), findsOneWidget);
      expect(fake.checkouts, isEmpty);

      await tester.enterText(find.byKey(const Key('checkout-quantity')), '1.5');
      await tester.tap(find.byKey(const Key('checkout-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Whole pieces only'), findsOneWidget);

      await tester.tap(find.byKey(const Key('checkout-person-Aisha')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('checkout-quantity')), '2');
      await tester.enterText(find.byKey(const Key('checkout-due')), 'soon');
      await tester.tap(find.byKey(const Key('checkout-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Use YYYY-MM-DD'), findsOneWidget);

      await tester.tap(find.byKey(const Key('checkout-due-7')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('checkout-note')),
        'titration',
      );
      await tester.tap(find.byKey(const Key('checkout-submit')));
      await tester.pumpAndSettle();

      expect(fake.checkouts, hasLength(1));
      final (id, quantity, person, note, dueAt) = fake.checkouts.single;
      expect(id, 'a1');
      expect(quantity, 2);
      expect(person, 'Aisha');
      expect(note, 'titration');
      final expectedDue = DateTime.now().add(const Duration(days: 7));
      expect(dueAt?.day, expectedDue.day);
      expect(dueAt?.hour, 23);
      expect(find.text('2 pcs checked out to Aisha'), findsOneWidget);
    });

    testWidgets('checkout form surfaces the migration hint', (tester) async {
      await _pump(
        tester,
        seed: InventoryState(apparatus: [_gear('a1', 'Balance')]),
        open: (context, ref) => showCheckoutSheet(context, 'a1'),
        failWith: StateError(checkoutsMigrationHint),
      );
      await tester.enterText(find.byKey(const Key('checkout-person')), 'Sara');
      await tester.tap(find.byKey(const Key('checkout-submit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('005_apparatus_checkouts.sql'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('checkout-submit')), findsOneWidget);
    });

    testWidgets('return form defaults to the outstanding pieces', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        seed: InventoryState(
          apparatus: [_gear('a1', 'Balance', quantity: 4)],
          checkouts: [_loan('c1', 'a1', quantity: 3, returned: 1)],
        ),
        open: (context, ref) => showReturnSheet(context, 'c1'),
      );
      final field = tester.widget<TextFormField>(
        find.byKey(const Key('return-quantity')),
      );
      expect(field.controller?.text, '2');

      await tester.enterText(find.byKey(const Key('return-quantity')), '3');
      await tester.tap(find.byKey(const Key('return-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Only 2 out'), findsOneWidget);
      expect(fake.returns, isEmpty);

      await tester.enterText(find.byKey(const Key('return-quantity')), '1');
      await tester.enterText(find.byKey(const Key('return-note')), 'chipped');
      await tester.tap(find.byKey(const Key('return-submit')));
      await tester.pumpAndSettle();
      expect(fake.returns.single, ('c1', 1.0, 'chipped'));
      expect(find.text('1 pcs back · 1 still out'), findsOneWidget);
    });

    testWidgets('shelf rows mark lent and overdue apparatus', (tester) async {
      tester.view.physicalSize = const Size(420, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(
                InventoryState(
                  apparatus: [_gear('a1', 'Balance'), _gear('a2', 'Burette')],
                  checkouts: [
                    _loan(
                      'c1',
                      'a1',
                      quantity: 2,
                      due: DateTime.now().subtract(const Duration(days: 1)),
                    ),
                    _loan('c2', 'a2', returnedAt: DateTime.now()),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(kind: ItemKind.apparatus),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mark-checkout')), findsOneWidget);
      expect(find.text('2 out · overdue'), findsOneWidget);
    });
  });
}
