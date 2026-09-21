import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';
import 'package:lab_wizard/features/reports/domain/report_stats.dart';

ConsumptionLog _log(
  String id,
  DateTime at, {
  required String itemId,
  InventoryAction action = InventoryAction.consume,
  double amount = 5,
  ItemKind kind = ItemKind.chemical,
}) => ConsumptionLog(
  id: id,
  itemId: itemId,
  itemType: kind,
  action: action,
  amount: amount,
  note: '',
  loggedAt: at,
  createdAt: at,
);

String _unitOf(String itemId) => switch (itemId) {
  'acetone' => 'mL',
  'salt' => 'g',
  _ => '',
};

void main() {
  final today = DateTime(2026, 9, 21, 12);
  final range = ReportRange.lastDays(7, today: today);

  test('totals are split by action and summed per unit', () {
    final logs = [
      _log('1', DateTime(2026, 9, 20), itemId: 'acetone', amount: 100),
      _log('2', DateTime(2026, 9, 21, 23), itemId: 'acetone', amount: 250),
      _log('3', DateTime(2026, 9, 19), itemId: 'salt', amount: 20),
      _log(
        '4',
        DateTime(2026, 9, 18),
        itemId: 'acetone',
        action: InventoryAction.restock,
        amount: 500,
      ),
      _log('5', DateTime(2026, 9, 14, 23, 59), itemId: 'acetone', amount: 9),
      _log('6', DateTime(2026, 9, 16), itemId: 'gone', amount: 1),
      _log(
        '7',
        DateTime(2026, 9, 16),
        itemId: 'beaker',
        kind: ItemKind.apparatus,
        action: InventoryAction.breakage,
        amount: 2,
      ),
    ];
    final stats = summarizePeriod(
      range,
      logs,
      kind: ItemKind.chemical,
      unitOf: _unitOf,
    );
    expect(stats.of(InventoryAction.consume).count, 4);
    expect(stats.of(InventoryAction.consume).quantityByUnit, {
      'mL': 350,
      'g': 20,
      '': 1,
    });
    expect(stats.of(InventoryAction.consume).quantityLabel, '350 mL · 20 g · 1');
    expect(stats.of(InventoryAction.restock).count, 1);
    expect(stats.of(InventoryAction.restock).quantityLabel, '500 mL');
    expect(stats.of(InventoryAction.breakage).count, 0);
    expect(stats.of(InventoryAction.breakage).quantityLabel, isEmpty);
    expect(stats.totalCount, 5);

    final gear = summarizePeriod(
      range,
      logs,
      kind: ItemKind.apparatus,
      unitOf: _unitOf,
    );
    expect(gear.of(InventoryAction.breakage).quantityByUnit, {'pcs': 2});
  });

  test('comparison with the previous period explains itself', () {
    final logs = [
      _log('1', DateTime(2026, 9, 20), itemId: 'acetone', amount: 100),
      _log('2', DateTime(2026, 9, 19), itemId: 'acetone', amount: 100),
      _log('3', DateTime(2026, 9, 18), itemId: 'acetone', amount: 100),
      _log('4', DateTime(2026, 9, 12), itemId: 'acetone', amount: 50),
      _log('5', DateTime(2026, 9, 10), itemId: 'acetone', amount: 50),
      _log(
        '6',
        DateTime(2026, 9, 11),
        itemId: 'acetone',
        action: InventoryAction.restock,
        amount: 200,
      ),
      _log(
        '7',
        DateTime(2026, 9, 20),
        itemId: 'salt',
        action: InventoryAction.breakage,
        amount: 1,
      ),
    ];
    final trend = TrendComparison.compute(
      range,
      logs,
      kind: ItemKind.chemical,
      unitOf: _unitOf,
    );
    expect(trend.previous.range.start, DateTime(2026, 9, 8));
    expect(trend.previous.range.end, DateTime(2026, 9, 14));
    expect(trend.countChange(InventoryAction.consume), closeTo(0.5, 1e-9));
    expect(trend.quantityChange(InventoryAction.consume, 'mL'), closeTo(2, 1e-9));
    expect(trend.countChange(InventoryAction.restock), -1);
    expect(trend.countChange(InventoryAction.breakage), isNull);
    expect(trend.describe(InventoryAction.consume), '+50% vs previous 7 days');
    expect(
      trend.describe(InventoryAction.restock),
      'none, 1 in the previous 7 days',
    );
    expect(trend.describe(InventoryAction.breakage), 'none in the previous 7 days');
    expect(trend.previousLabel, 'previous 7 days');

    final empty = TrendComparison.compute(
      ReportRange.month(2026, 5),
      logs,
      kind: ItemKind.chemical,
      unitOf: _unitOf,
    );
    expect(empty.describe(InventoryAction.consume), 'none in either period');
    expect(empty.previousLabel, 'previous month');
    expect(
      TrendComparison.compute(
        ReportRange.custom(DateTime(2026, 9, 10), DateTime(2026, 9, 21)),
        logs,
        kind: ItemKind.chemical,
        unitOf: _unitOf,
      ).previousLabel,
      'previous 12 days',
    );
  });

  test('changes are formatted with a real minus sign', () {
    expect(formatChange(0.25), '+25%');
    expect(formatChange(-0.4), '−40%');
    expect(formatChange(0.001), '0%');
    expect(formatChange(2), '+200%');
  });
}
