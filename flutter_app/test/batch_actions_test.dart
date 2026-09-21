import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/batch_sheets.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed, {this.failFor = const {}});

  final InventoryState seed;
  final Set<String> failFor;
  final restocks = <(String, double, String)>[];
  final thresholds = <(String, double)>[];
  final fields = <(String, String, String)>[];
  final deletions = <String>[];

  @override
  InventoryState build() => seed;

  @override
  Future<ConsumptionLog> applyAction({
    required String itemId,
    required ItemKind itemType,
    required InventoryAction action,
    required double amount,
    required String note,
    required DateTime date,
  }) async {
    if (failFor.contains(itemId)) throw StateError('Item not found');
    restocks.add((itemId, amount, note));
    state = state.copyWith(
      chemicals: state.chemicals
          .map(
            (item) => item.id == itemId
                ? item.copyWith(quantity: item.quantity + amount)
                : item,
          )
          .toList(),
    );
    return ConsumptionLog(
      id: 'log-$itemId',
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
  Future<void> updateItem({
    required ItemKind type,
    required String id,
    required Map<String, dynamic> changes,
    bool force = false,
  }) async {
    if (changes.containsKey('low_stock_threshold')) {
      thresholds.add((id, (changes['low_stock_threshold'] as num).toDouble()));
      return;
    }
    final entry = changes.entries.single;
    fields.add((id, entry.key, entry.value as String));
    state = state.copyWith(
      chemicals: state.chemicals
          .map(
            (item) => item.id == id && entry.key == 'location'
                ? item.copyWith(location: entry.value as String)
                : item,
          )
          .toList(),
    );
  }

  @override
  Future<void> deleteItem(ItemKind type, String id) async {
    if (failFor.contains(id)) throw StateError('permission denied');
    deletions.add(id);
    state = state.copyWith(
      chemicals: state.chemicals.where((item) => item.id != id).toList(),
    );
  }
}

List<Chemical> _chemicals(int count) => [
  for (var index = 0; index < count; index++)
    Chemical(
      id: 'chem-$index',
      name: 'Reagent ${String.fromCharCode(65 + index)}',
      formula: 'F$index',
      unit: 'mL',
      quantity: 50,
      initialQuantity: 100,
      lowStockThreshold: index == 1 ? 4 : 10,
      notes: '',
      qrCode: 'qr-$index',
      createdAt: DateTime(2026, 1, 1 + index),
      location: index == 1 ? 'Cabinet B' : null,
    ),
];

Future<_FakeInventory> _pump(
  WidgetTester tester,
  InventoryState seed, {
  Set<String> failFor = const {},
  bool online = true,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => fake = _FakeInventory(seed, failFor: failFor),
        ),
        isOnlineProvider.overrideWithValue(() async => online),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const InventoryScreen(kind: ItemKind.chemical),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _selectFirst(WidgetTester tester, int count) async {
  await tester.longPress(find.text('Reagent A'));
  await tester.pumpAndSettle();
  for (var index = 1; index < count; index++) {
    await tester.tap(find.text('Reagent ${String.fromCharCode(65 + index)}'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('validation', () {
    test('amounts must be positive numbers, whole for apparatus', () {
      expect(validateBatchAmount('', wholeNumbers: false), 'Enter an amount');
      expect(validateBatchAmount('abc', wholeNumbers: false), 'Enter a number');
      expect(
        validateBatchAmount('0', wholeNumbers: false),
        'Must be greater than zero',
      );
      expect(
        validateBatchAmount('0', wholeNumbers: false, allowZero: true),
        isNull,
      );
      expect(
        validateBatchAmount('-1', wholeNumbers: false, allowZero: true),
        'Cannot be negative',
      );
      expect(
        validateBatchAmount('1.5', wholeNumbers: true),
        'Use whole numbers for apparatus',
      );
      expect(validateBatchAmount('2.5', wholeNumbers: false), isNull);
    });

    test('runBatch continues after failures and reports them', () async {
      final progress = <int>[];
      final outcome = await runBatch<String>(
        items: ['a', 'b', 'c'],
        idOf: (item) => item,
        nameOf: (item) => item.toUpperCase(),
        step: (item) async {
          if (item == 'b') throw StateError('Insufficient stock: only 1');
        },
        onProgress: progress.add,
      );
      expect(outcome.succeeded, 2);
      expect(outcome.failures.single.name, 'B');
      expect(outcome.failures.single.message, contains('less stock'));
      expect(progress, [1, 2, 3]);
    });
  });

  group('selection mode', () {
    testWidgets('long-press selects, select shown, close clears', (
      tester,
    ) async {
      await _pump(tester, InventoryState(chemicals: _chemicals(6)));
      expect(find.byKey(const Key('selection-bar')), findsNothing);

      await tester.longPress(find.text('Reagent A'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-bar')), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const Key('selection-actions')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.text('Reagent B'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('selection-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('6 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('selection-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-bar')), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('BATCH-01 restock', () {
    testWidgets('applies one restock per item with its own amount', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        InventoryState(chemicals: _chemicals(3)),
      );
      await _selectFirst(tester, 2);
      await tester.tap(find.byKey(const Key('selection-restock')));
      await tester.pumpAndSettle();

      // Empty amounts are rejected before anything is recorded.
      await tester.tap(find.byKey(const Key('batch-restock-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsNWidgets(2));
      expect(fake.restocks, isEmpty);

      await tester.enterText(find.byKey(const Key('batch-same-amount')), '5');
      await tester.tap(find.byKey(const Key('batch-apply-same')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('batch-amount-chem-1')),
        '7.5',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('batch-restock-submit')));
      await tester.pumpAndSettle();

      expect(fake.restocks, [
        ('chem-0', 5.0, 'Batch restock'),
        ('chem-1', 7.5, 'Batch restock'),
      ]);
      expect(find.byKey(const Key('batch-restock-submit')), findsNothing);
      expect(find.text('2 items restocked'), findsOneWidget);
    });

    testWidgets('a failing item is reported and can be retried alone', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        InventoryState(chemicals: _chemicals(3)),
        failFor: {'chem-1'},
      );
      await _selectFirst(tester, 2);
      await tester.tap(find.byKey(const Key('selection-restock')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('batch-same-amount')), '3');
      await tester.tap(find.byKey(const Key('batch-apply-same')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-restock-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('batch-report')), findsOneWidget);
      expect(find.text('1 restocked · 1 failed'), findsOneWidget);
      expect(find.text('Reagent B'), findsWidgets);
      expect(fake.restocks.map((entry) => entry.$1), ['chem-0']);

      fake.failFor.clear();
      await tester.tap(find.byKey(const Key('batch-retry-failed')));
      await tester.pumpAndSettle();
      expect(fake.restocks.map((entry) => entry.$1), ['chem-0', 'chem-1']);
      expect(find.text('2 items restocked'), findsOneWidget);
    });
  });

  group('BATCH-02 threshold', () {
    testWidgets('previews old → new and skips unchanged items', (tester) async {
      final fake = await _pump(
        tester,
        InventoryState(chemicals: _chemicals(3)),
      );
      await _selectFirst(tester, 3);
      await tester.tap(find.byKey(const Key('selection-threshold')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a threshold'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('batch-threshold-value')),
        '-2',
      );
      await tester.pumpAndSettle();
      expect(find.text('Cannot be negative'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('batch-threshold-value')),
        '4',
      );
      await tester.pumpAndSettle();
      expect(find.text('min 10 → 4 mL'), findsNWidgets(2));
      expect(find.text('already 4 mL — unchanged'), findsOneWidget);
      expect(find.text('Update 2 items'), findsOneWidget);

      await tester.tap(find.byKey(const Key('batch-threshold-submit')));
      await tester.pumpAndSettle();
      expect(fake.thresholds, [('chem-0', 4.0), ('chem-2', 4.0)]);
      expect(find.text('Threshold updated for 2 items'), findsOneWidget);
    });
  });

  group('BATCH-03 location / category', () {
    testWidgets('moves selected chemicals to one location with a preview', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        InventoryState(chemicals: _chemicals(3)),
      );
      await _selectFirst(tester, 3);
      await tester.tap(find.byKey(const Key('selection-field')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a location'), findsOneWidget);
      expect(find.text('no location yet'), findsNWidgets(2));

      // Existing locations are offered as one-tap suggestions.
      await tester.tap(find.byKey(const Key('location-suggestion-Cabinet B')));
      await tester.pumpAndSettle();
      expect(find.text('none → Cabinet B'), findsNWidgets(2));
      expect(find.text('already Cabinet B — unchanged'), findsOneWidget);
      expect(find.text('Update 2 items'), findsOneWidget);

      await tester.tap(find.byKey(const Key('batch-field-submit')));
      await tester.pumpAndSettle();
      expect(fake.fields, [
        ('chem-0', 'location', 'Cabinet B'),
        ('chem-2', 'location', 'Cabinet B'),
      ]);
      expect(fake.thresholds, isEmpty);
      expect(find.text('Location updated for 2 items'), findsOneWidget);
    });
  });

  group('BATCH-04 delete', () {
    testWidgets('large deletions need a typed confirmation', (tester) async {
      final fake = await _pump(
        tester,
        InventoryState(chemicals: _chemicals(6)),
        height: 1500,
      );
      await _selectFirst(tester, 5);
      await tester.tap(find.byKey(const Key('selection-delete')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('5 items and 0 history entries will be removed'),
        findsOneWidget,
      );
      final submit = find.byKey(const Key('batch-delete-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('batch-delete-confirmation')),
        'delete',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(fake.deletions, hasLength(5));
      expect(find.text('5 items deleted'), findsOneWidget);
      expect(find.text('Reagent F'), findsOneWidget);
    });

    testWidgets('offline devices and unsynced items are blocked', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        InventoryState(chemicals: _chemicals(3)),
        online: false,
      );
      await _selectFirst(tester, 2);
      await tester.tap(find.byKey(const Key('selection-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batch-delete-confirmation')), findsNothing);
      await tester.tap(find.byKey(const Key('batch-delete-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batch-delete-blocker')), findsOneWidget);
      expect(fake.deletions, isEmpty);
    });

    testWidgets('items with queued changes cannot be deleted yet', (
      tester,
    ) async {
      await _pump(
        tester,
        InventoryState(
          chemicals: _chemicals(3),
          outbox: [
            PendingOperation(
              id: 'op-1',
              userId: 'u1',
              type: 'inventory_action',
              payload: const {'item_id': 'chem-1', 'action': 'consume'},
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
      await _selectFirst(tester, 2);
      await tester.tap(find.byKey(const Key('selection-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batch-delete-unsynced')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('batch-delete-submit')))
            .onPressed,
        isNull,
      );
    });
  });
}
