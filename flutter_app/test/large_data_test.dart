import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';
import 'package:lab_wizard/features/reports/domain/report_stats.dart';
import 'package:lab_wizard/features/reports/domain/runout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

/// TEST-06: the shelf and the report maths with 1,000 items and 20,000 log
/// entries. Budgets are deliberately loose (widget tests run unoptimised
/// on shared CI runners); the structural checks — the list stays lazy, a
/// search narrows to one row, the A–Z jump lands — are the hard part.
const _items = 1000;
const _logs = 20000;
const _buildBudget = Duration(seconds: 20);
const _interactionBudget = Duration(seconds: 8);
const _mathBudget = Duration(seconds: 4);

final _now = DateTime.now();

List<Chemical> _chemicals() => [
  for (var index = 0; index < _items; index++)
    Chemical(
      id: 'c$index',
      name: 'Reagent ${index.toString().padLeft(4, '0')} '
          '${String.fromCharCode(65 + index % 26)}',
      formula: 'F$index',
      unit: index.isEven ? 'mL' : 'g',
      quantity: (index % 7 == 0) ? 0 : (index % 5 == 0 ? 3 : 250),
      initialQuantity: 500,
      lowStockThreshold: 10,
      notes: '',
      qrCode: 'qr-$index',
      createdAt: DateTime(2026, 1, 1).add(Duration(minutes: index)),
    ),
];

List<ConsumptionLog> _logsFor(List<Chemical> chemicals) => [
  for (var index = 0; index < _logs; index++)
    ConsumptionLog(
      id: 'l$index',
      itemId: chemicals[index % chemicals.length].id,
      itemType: ItemKind.chemical,
      action: index % 9 == 0
          ? InventoryAction.restock
          : InventoryAction.consume,
      amount: 1 + index % 4,
      note: '',
      loggedAt: _now.subtract(Duration(minutes: index * 5)),
      createdAt: _now.subtract(Duration(minutes: index * 5)),
    ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TEST-06 shelf with $_items items', () {
    for (final compact in [false, true]) {
      testWidgets(compact ? 'compact rows' : 'detailed cards', (tester) async {
        SharedPreferences.setMockInitialValues({
          'inventory_density': compact ? 'compact' : 'detailed',
        });
        final chemicals = _chemicals();
        final watch = Stopwatch()..start();
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          state: InventoryState(chemicals: chemicals, lastUpdated: _now),
          size: const Size(420, 900),
        );
        watch.stop();
        expect(watch.elapsed, lessThan(_buildBudget), reason: 'first build');
        expect(find.text('$_items of $_items'), findsOneWidget);
        // Lazy: only the rows on (and just off) screen exist.
        final built = find.textContaining('Reagent ').evaluate().length;
        expect(built, lessThan(60), reason: 'built rows: $built');

        // Search narrows to one row quickly.
        watch
          ..reset()
          ..start();
        await tester.enterText(find.byType(TextField), 'Reagent 0999');
        await tester.pumpAndSettle();
        watch.stop();
        expect(watch.elapsed, lessThan(_interactionBudget), reason: 'search');
        expect(find.text('1 of $_items'), findsOneWidget);
        expect(find.textContaining('Reagent 0999'), findsOneWidget);

        // Filter and sort re-run over all items.
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        watch
          ..reset()
          ..start();
        await tester.tap(find.text('critical'));
        await tester.pumpAndSettle();
        watch.stop();
        expect(watch.elapsed, lessThan(_interactionBudget), reason: 'filter');
        final empties = chemicals.where((c) => c.quantity == 0).length;
        expect(find.text('$empties of $_items'), findsOneWidget);
        await tester.tap(find.text('all'));
        await tester.pumpAndSettle();

        // A–Z jump across the whole list.
        watch
          ..reset()
          ..start();
        await tester.tap(find.byKey(const Key('alpha-R')));
        await tester.pumpAndSettle();
        watch.stop();
        expect(watch.elapsed, lessThan(_interactionBudget), reason: 'jump');
        expect(find.textContaining('Reagent 0000'), findsOneWidget);

        // Fling through a few screens without errors.
        for (var i = 0; i < 6; i++) {
          await tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -1500),
            3000,
          );
          await tester.pumpAndSettle();
        }
        final afterFling = find.textContaining('Reagent ').evaluate().length;
        expect(afterFling, lessThan(60), reason: 'still lazy: $afterFling');
      });
    }
  });

  group('TEST-06 report maths with $_logs entries', () {
    late List<Chemical> chemicals;
    late List<ConsumptionLog> logs;

    setUpAll(() {
      chemicals = _chemicals();
      logs = _logsFor(chemicals);
    });

    test('buckets, trends and run-out estimates stay within budget', () {
      final range = ReportRange.lastDays(30, today: _now);
      final watch = Stopwatch()..start();
      final buckets = bucketize(range, logs.map((log) => log.loggedAt));
      final trend = TrendComparison.compute(
        range,
        logs,
        kind: ItemKind.chemical,
        unitOf: (_) => 'mL',
      );
      final runOut = runOutReportForChemicals(chemicals, logs, now: _now);
      watch.stop();
      expect(watch.elapsed, lessThan(_mathBudget), reason: 'report maths');
      expect(buckets, hasLength(30));
      expect(
        buckets.fold<int>(0, (sum, bucket) => sum + bucket.count),
        logs.where((log) => range.contains(log.loggedAt)).length,
      );
      expect(trend.current.of(InventoryAction.consume).count, greaterThan(0));
      expect(runOut.estimates.length + runOut.withoutEstimate, _items);
    });
  });
}
