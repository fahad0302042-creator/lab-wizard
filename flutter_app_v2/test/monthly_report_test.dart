import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/inventory/domain/models.dart';
import 'package:lab_wizard_v2/features/reports/domain/monthly_report.dart';

final _month = DateTime(2026, 10);

Chemical _chemical(
  String id,
  String name, {
  double quantity = 100,
  String formula = 'X',
  String unit = 'g',
}) => Chemical(
  id: id,
  name: name,
  formula: formula,
  unit: unit,
  quantity: quantity,
  initialQuantity: 1000,
  lowStockThreshold: 0,
  notes: '',
  qrCode: '',
  createdAt: DateTime(2026),
);

Apparatus _apparatus(
  String id,
  String name, {
  double quantity = 5,
}) => Apparatus(
  id: id,
  name: name,
  category: 'glassware',
  quantity: quantity,
  initialQuantity: 10,
  lowStockThreshold: 0,
  notes: '',
  createdAt: DateTime(2026),
);

ConsumptionLog _log(
  String itemId,
  InventoryAction action,
  double amount, {
  ItemKind kind = ItemKind.chemical,
  DateTime? at,
}) => ConsumptionLog(
  id: '$itemId-${action.name}-$amount-${at?.day ?? 1}',
  itemId: itemId,
  itemType: kind,
  action: action,
  amount: amount,
  note: '',
  loggedAt: at ?? DateTime(2026, 10, 4),
  createdAt: DateTime(2026, 10, 4),
);

void main() {
  group('monthly report rows', () {
    test('only items with an entry this month appear', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [
          _chemical('a', 'Acetone'),
          _chemical('b', 'Ethanol'),
        ],
        apparatus: const [],
        logs: [_log('a', InventoryAction.consume, 20)],
        month: _month,
      );
      expect(report.rows.map((row) => row.id), ['a']);
      expect(report.itemsConsumed, 1);
      expect(report.events, 1);
    });

    test('a different month is ignored', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [_chemical('a', 'Acetone')],
        apparatus: const [],
        logs: [
          _log('a', InventoryAction.consume, 20, at: DateTime(2026, 9, 30)),
        ],
        month: _month,
      );
      expect(report.isEmpty, isTrue);
      expect(report.events, 0);
    });

    test('restocking inside the month still shows, while the two "have" '
        'columns differ', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [
          _chemical('a', 'Acetone', quantity: 900),
          _chemical('b', 'Ethanol', quantity: 400),
        ],
        apparatus: const [],
        logs: [
          _log('a', InventoryAction.restock, 500),
          _log('a', InventoryAction.consume, 200),
        ],
        month: _month,
      );
      final row = report.rows.single;
      expect(row.left, 900);
      expect(row.used, 200);
      expect(row.added, 500);
      // left + used = 1100 now have; 1100 - 500 added = 600 at the start.
      expect(row.nowHave, 1100);
      expect(row.weHave, 600);
      expect(report.hasAdditions, isTrue);
    });

    test('a month with no restocks hides the added columns entirely', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [_chemical('a', 'Acetone', quantity: 359)],
        apparatus: const [],
        logs: [_log('a', InventoryAction.consume, 10)],
        month: _month,
      );
      final row = report.rows.single;
      expect(row.left, 359);
      expect(row.used, 10);
      expect(row.nowHave, 369);
      expect(row.weHave, 369);
      expect(report.hasAdditions, isFalse);
      expect(report.footnote, contains('We have − used = left.'));
    });

    test('breakage counts as used, and apparatus is counted separately', () {
      final report = buildMonthlyReport(
        kind: ItemKind.apparatus,
        chemicals: [_chemical('a', 'Acetone')],
        apparatus: [
          _apparatus('c', 'Beaker'),
          _apparatus('d', 'Burette'),
        ],
        logs: [
          _log('a', InventoryAction.consume, 50),
          _log('c', InventoryAction.breakage, 2, kind: ItemKind.apparatus),
          _log('d', InventoryAction.restock, 3, kind: ItemKind.apparatus),
        ],
        month: _month,
      );
      expect(report.rows.map((row) => row.id), ['c', 'd']);
      expect(report.itemsConsumed, 1);
      expect(report.events, 1);
      expect(report.rows.first.used, 2);
      expect(report.rows.first.unit, 'pcs');
    });

    test('rows are alphabetical, ignoring case', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [
          _chemical('1', 'zinc sulphate'),
          _chemical('2', 'Acetone'),
          _chemical('3', '2,4-Dinitrophenylhydrazine'),
          _chemical('4', 'Barium chloride'),
        ],
        apparatus: const [],
        logs: [
          for (final id in ['1', '2', '3', '4'])
            _log(id, InventoryAction.consume, 1),
        ],
        month: _month,
      );
      expect(report.rows.map((row) => row.name), [
        '2,4-Dinitrophenylhydrazine',
        'Acetone',
        'Barium chloride',
        'zinc sulphate',
      ]);
    });

    test('a restock-only row is not counted as consumed', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [_chemical('a', 'Acetone', quantity: 500)],
        apparatus: const [],
        logs: [_log('a', InventoryAction.restock, 250)],
        month: _month,
      );
      expect(report.rows.single.used, 0);
      expect(report.itemsConsumed, 0);
      expect(report.events, 0);
      expect(report.hasAdditions, isTrue);
    });

    test('low stock counts the whole shelf, not just this month', () {
      final chemicals = [
        _chemical('a', 'Acetone', quantity: 0),
        _chemical('b', 'Ethanol', quantity: 900),
      ];
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: chemicals,
        apparatus: const [],
        logs: [_log('a', InventoryAction.consume, 5)],
        month: _month,
      );
      expect(report.lowStockCount, 1);
    });

    test('amounts that would show float noise are rounded to two places', () {
      final report = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [_chemical('a', 'Acetone', quantity: 0.3)],
        apparatus: const [],
        logs: [
          _log('a', InventoryAction.consume, 0.1),
          _log('a', InventoryAction.consume, 0.2),
        ],
        month: _month,
      );
      expect(report.rows.single.used, 0.3);
      expect(report.rows.single.left, 0.3);
      expect(report.rows.single.nowHave, 0.6);
    });

    test('the title names the shelf', () {
      final chemicals = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: const [],
        apparatus: const [],
        logs: const [],
        month: _month,
      );
      final apparatus = buildMonthlyReport(
        kind: ItemKind.apparatus,
        chemicals: const [],
        apparatus: const [],
        logs: const [],
        month: _month,
      );
      expect(chemicals.title, 'Chemicals Consumption Report');
      expect(apparatus.title, 'Apparatus Usage Report');
      expect(chemicals.periodLabel, 'October 2026');
    });
  });
}
