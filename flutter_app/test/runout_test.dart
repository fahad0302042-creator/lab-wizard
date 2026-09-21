import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/domain/runout.dart';

final _today = DateTime(2026, 9, 21, 14);

ConsumptionLog _use(
  String id,
  int daysAgo,
  double amount, {
  String itemId = 'c1',
  InventoryAction action = InventoryAction.consume,
}) {
  final at = DateTime(_today.year, _today.month, _today.day - daysAgo, 10);
  return ConsumptionLog(
    id: id,
    itemId: itemId,
    itemType: ItemKind.chemical,
    action: action,
    amount: amount,
    note: '',
    loggedAt: at,
    createdAt: at,
  );
}

Chemical _chemical(String id, String name, double quantity) => Chemical(
  id: id,
  name: name,
  formula: 'X',
  unit: 'mL',
  quantity: quantity,
  initialQuantity: 100,
  lowStockThreshold: 10,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
);

RunOutResult _estimate(double quantity, List<ConsumptionLog> logs) =>
    estimateRunOut(
      itemId: 'c1',
      name: 'Acetone',
      unit: 'mL',
      quantity: quantity,
      logs: logs,
      now: _today,
    );

void main() {
  test('an estimate explains the pace behind it', () {
    final result = _estimate(40, [
      _use('1', 0, 10),
      _use('2', 5, 10),
      _use('3', 19, 10), // 20 days of history including today
      _use('4', 2, 500, action: InventoryAction.restock), // ignored
      _use('5', 3, 7, itemId: 'other'), // ignored
      _use('6', 95, 999), // outside the 90-day window
    ]);
    expect(result, isA<RunOutEstimate>());
    final estimate = result as RunOutEstimate;
    expect(estimate.entries, 3);
    expect(estimate.consumedTotal, 30);
    expect(estimate.historyDays, 20);
    expect(estimate.dailyRate, 1.5);
    expect(estimate.daysLeft, 26);
    expect(estimate.runsOutOn, DateTime(2026, 10, 17));
    expect(estimate.headline, '~26 days · 17 Oct');
    expect(
      estimate.explanation,
      '40 mL left; 3 uses totalling 30 mL over the last 20 days, '
      'about 1.5 mL per day.',
    );
    expect(estimate.urgent, isFalse);
    expect(estimate.soon, isTrue);
  });

  test('no estimate without adequate history', () {
    expect(
      (_estimate(40, []) as RunOutMissing).gap,
      RunOutGap.noUse,
    );
    expect(
      (_estimate(40, [_use('1', 0, 10), _use('2', 30, 10)]) as RunOutMissing)
          .gap,
      RunOutGap.tooFewEntries,
    );
    expect(
      (_estimate(40, [
                _use('1', 0, 10),
                _use('2', 1, 10),
                _use('3', 5, 10), // only 6 days of history
              ])
              as RunOutMissing)
          .gap,
      RunOutGap.tooShortHistory,
    );
    // Exactly the minimum span counts.
    expect(
      _estimate(40, [_use('1', 0, 10), _use('2', 1, 10), _use('3', 6, 10)]),
      isA<RunOutEstimate>(),
    );
    // Zero-amount entries are not uses.
    expect(
      (_estimate(40, [_use('1', 0, 0), _use('2', 1, 0), _use('3', 9, 0)])
              as RunOutMissing)
          .gap,
      RunOutGap.noUse,
    );
  });

  test('empty stock and urgent cases read naturally', () {
    final logs = [_use('1', 0, 10), _use('2', 4, 10), _use('3', 9, 10)];
    final out = _estimate(0, logs) as RunOutEstimate;
    expect(out.isOut, isTrue);
    expect(out.daysLeft, 0);
    expect(out.headline, 'already out');
    final today = _estimate(2, logs) as RunOutEstimate; // 3 mL/day
    expect(today.daysLeft, 0);
    expect(today.headline, 'today');
    expect(today.urgent, isTrue);
    final one = _estimate(4, logs) as RunOutEstimate;
    expect(one.headline, '~1 day · 22 Sep');
  });

  test('the shelf report sorts soonest first and counts the gaps', () {
    final logs = [
      _use('1', 0, 10, itemId: 'a'),
      _use('2', 5, 10, itemId: 'a'),
      _use('3', 19, 10, itemId: 'a'),
      _use('4', 0, 1, itemId: 'b'),
      _use('5', 5, 1, itemId: 'b'),
      _use('6', 19, 1, itemId: 'b'),
      _use('7', 0, 1, itemId: 'c'),
    ];
    final report = runOutReportForChemicals([
      _chemical('a', 'Acetone', 300),
      _chemical('b', 'Buffer', 3),
      _chemical('c', 'Citric acid', 50),
      _chemical('d', 'Dye', 50),
    ], logs, now: _today);
    expect(report.estimates.map((e) => e.name), ['Buffer', 'Acetone']);
    expect(report.estimates.first.daysLeft, 20);
    expect(report.estimates.last.daysLeft, 200);
    expect(report.gaps, {RunOutGap.tooFewEntries: 1, RunOutGap.noUse: 1});
    expect(report.withoutEstimate, 2);
    expect(
      report.gapSummary,
      '2 items have too little history (need 3+ uses over 7+ days in the '
      'last 90 days).',
    );
    expect(
      runOutReportForChemicals([_chemical('a', 'Acetone', 1)], [], now: _today)
          .gapSummary,
      '1 item has too little history (need 3+ uses over 7+ days in the '
      'last 90 days).',
    );
  });
}
