import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/domain/asset_reports.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';

final _today = DateTime(2026, 9, 21, 11);

DateTime _day(int offset, [int hour = 10]) =>
    DateTime(_today.year, _today.month, _today.day + offset, hour);

Chemical _chemical(String id, String name, {DateTime? expiry}) => Chemical(
  id: id,
  name: name,
  formula: 'X',
  unit: 'mL',
  quantity: 5,
  initialQuantity: 10,
  lowStockThreshold: 1,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  expiryDate: expiry,
);

ConsumptionLog _log(
  String id,
  DateTime at, {
  required String itemId,
  ItemKind kind = ItemKind.apparatus,
  InventoryAction action = InventoryAction.breakage,
  double amount = 1,
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

void main() {
  test('relative day wording', () {
    expect(relativeDays(0), 'today');
    expect(relativeDays(1), 'tomorrow');
    expect(relativeDays(-1), 'yesterday');
    expect(relativeDays(12), 'in 12 days');
    expect(relativeDays(-3), '3 days ago');
    expect(daysFromToday(DateTime(2026, 9, 25, 23), today: _today), 4);
    expect(daysFromToday(DateTime(2026, 9, 19, 1), today: _today), -2);
  });

  test('expiry view splits expired, soon, later and undated', () {
    final report = expiryReport([
      _chemical('a', 'Old acid', expiry: _day(-40)),
      _chemical('b', 'Buffer', expiry: _day(-1)),
      _chemical('c', 'Citrate', expiry: _day(30)),
      _chemical('d', 'Dye', expiry: _day(3)),
      _chemical('e', 'Ethanol', expiry: _day(31)),
      _chemical('f', 'Formalin'),
    ], now: _today);
    expect(report.expired.map((row) => row.chemical.name), [
      'Old acid',
      'Buffer',
    ]);
    expect(report.expired.first.days, -40);
    expect(report.expired.first.when, '12 Aug 2026 · expired 40 days ago');
    expect(report.expiringSoon.map((row) => row.chemical.name), [
      'Dye',
      'Citrate',
    ]);
    expect(report.expiringSoon.first.when, '24 Sep 2026 · in 3 days');
    expect(report.later, 1);
    expect(report.undated, 1);
    expect(report.isEmpty, isFalse);
    expect(expiryReport([_chemical('f', 'Formalin')], now: _today).isEmpty, isTrue);
  });

  test('damage view groups incidents per item inside the range', () {
    final range = ReportRange.lastDays(7, today: _today);
    final report = damageReport(
      range,
      [
        _log('1', _day(0), itemId: 'beaker', amount: 2),
        _log('2', _day(-2), itemId: 'beaker', amount: 1),
        _log('3', _day(-3), itemId: 'flask', amount: 4),
        _log('4', _day(-9), itemId: 'flask', amount: 40), // outside
        _log('5', _day(-1), itemId: 'flask', action: InventoryAction.consume),
        _log('6', _day(-1), itemId: 'acid', kind: ItemKind.chemical),
      ],
      kind: ItemKind.apparatus,
      nameOf: (id) => id == 'beaker' ? 'Beaker' : 'Flask',
      unitOf: (_) => 'pcs',
    );
    expect(report.rows.map((row) => row.name), ['Flask', 'Beaker']);
    expect(report.rows.first.amount, 4);
    expect(report.rows.last.incidents, 2);
    expect(report.rows.last.amount, 3);
    expect(report.rows.last.lastAt, _day(0));
    expect(report.incidents, 3);
    expect(
      damageReport(
        range,
        const [],
        kind: ItemKind.apparatus,
        nameOf: (_) => '',
        unitOf: (_) => '',
      ).isEmpty,
      isTrue,
    );
  });

  test('overdue loans are listed most overdue first', () {
    final report = loanReport(
      [
        ApparatusCheckout(
          id: 'l1',
          apparatusId: 'a',
          quantity: 2,
          person: 'Ali',
          checkedOutAt: _day(-10),
          dueAt: _day(-3),
        ),
        ApparatusCheckout(
          id: 'l2',
          apparatusId: 'a',
          quantity: 1,
          person: 'Sara',
          checkedOutAt: _day(-10),
          dueAt: _day(0, 8), // earlier today
        ),
        ApparatusCheckout(
          id: 'l3',
          apparatusId: 'b',
          quantity: 1,
          checkedOutAt: _day(-10),
          dueAt: _day(2),
        ),
        ApparatusCheckout(
          id: 'l4',
          apparatusId: 'b',
          quantity: 1,
          checkedOutAt: _day(-30),
          dueAt: _day(-20),
          returnedQuantity: 1,
          returnedAt: _day(-19),
        ),
        ApparatusCheckout(
          id: 'l5',
          apparatusId: 'b',
          quantity: 1,
          checkedOutAt: _day(-1),
        ),
      ],
      nameOf: (id) => id == 'a' ? 'Beaker' : 'Flask',
      now: _today,
    );
    expect(report.openLoans, 4);
    expect(report.overdue.map((loan) => loan.checkout.id), ['l1', 'l2']);
    expect(report.overdue.first.daysOverdue, 3);
    expect(report.overdue.first.when, '3 days overdue');
    expect(report.overdue.first.apparatusName, 'Beaker');
    expect(report.overdue.last.when, 'due today');
  });

  test('maintenance and calibration due, with completions in range', () {
    final range = ReportRange.lastDays(30, today: _today);
    final report = serviceReport(
      [
        ApparatusService(
          id: 's1',
          apparatusId: 'a',
          kind: ServiceKind.calibration,
          createdAt: _day(-40),
          dueAt: _day(-5),
        ),
        ApparatusService(
          id: 's2',
          apparatusId: 'a',
          kind: ServiceKind.maintenance,
          title: 'Grease bearings',
          createdAt: _day(-40),
          dueAt: _day(10),
        ),
        ApparatusService(
          id: 's3',
          apparatusId: 'b',
          kind: ServiceKind.maintenance,
          createdAt: _day(-40),
          dueAt: _day(40),
        ),
        ApparatusService(
          id: 's4',
          apparatusId: 'b',
          kind: ServiceKind.calibration,
          createdAt: _day(-40),
          dueAt: _day(-2),
          completedAt: _day(-1),
        ),
        ApparatusService(
          id: 's5',
          apparatusId: 'b',
          kind: ServiceKind.calibration,
          createdAt: _day(-90),
          dueAt: _day(-60),
          completedAt: _day(-50),
        ),
        ApparatusService(
          id: 's6',
          apparatusId: 'b',
          kind: ServiceKind.maintenance,
          createdAt: _day(-1),
        ),
      ],
      range: range,
      nameOf: (id) => id == 'a' ? 'Balance' : 'Pump',
      now: _today,
    );
    expect(report.due.map((row) => row.service.id), ['s1', 's2']);
    expect(report.due.first.when, 'overdue by 5 days');
    expect(report.due.first.apparatusName, 'Balance');
    expect(report.due.last.when, 'due in 10 days');
    expect(report.openTasks, 4);
    expect(report.completedInRange, 1);
  });
}
