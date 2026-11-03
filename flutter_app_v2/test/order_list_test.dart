import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/inventory/domain/item_view.dart';
import 'package:lab_wizard_v2/features/inventory/domain/models.dart';
import 'package:lab_wizard_v2/features/reports/data/closed_months.dart';
import 'package:lab_wizard_v2/features/reports/data/order_list.dart';
import 'package:lab_wizard_v2/features/reports/domain/monthly_report.dart';

ItemView _item({
  required String name,
  required double quantity,
  double threshold = 0,
  String unit = 'g',
  String subtitle = 'X',
  ItemKind kind = ItemKind.chemical,
}) => ItemView(
  id: name,
  kind: kind,
  name: name,
  subtitle: subtitle,
  notes: '',
  unit: unit,
  quantity: quantity,
  initialQuantity: 1000,
  threshold: threshold,
);

void main() {
  group('order list', () {
    test('names every item with what is left and the level it crossed', () {
      final text = orderListText(
        [
          _item(name: 'Acetone', quantity: 40, threshold: 100, unit: 'mL'),
          _item(name: 'Beaker', quantity: 0, unit: 'pcs'),
        ],
        at: DateTime(2026, 11, 3),
      );
      expect(text, contains('3 Nov 2026'));
      expect(text, contains('2 items'));
      expect(text, contains('Acetone (X): 40 mL left'));
      expect(text, contains('order level 100 mL'));
      expect(text, contains('Beaker (X): 0 pcs left'));
      expect(text, contains('no order level set'));
    });

    test('one item reads as one item, not "1 items"', () {
      final text = orderListText(
        [_item(name: 'Acetone', quantity: 1, threshold: 5)],
        at: DateTime(2026, 11, 3),
      );
      expect(text, contains('1 item'));
      expect(text, isNot(contains('1 items')));
    });
  });

  group('closing a month', () {
    MonthlyReport report() => buildMonthlyReport(
      kind: ItemKind.chemical,
      chemicals: [
        Chemical(
          id: 'a',
          name: 'Acetone',
          formula: 'C3H6O',
          unit: 'mL',
          quantity: 400,
          initialQuantity: 1000,
          lowStockThreshold: 100,
          notes: '',
          qrCode: '',
          createdAt: DateTime(2026),
        ),
      ],
      apparatus: const [],
      logs: [
        ConsumptionLog(
          id: 'log',
          itemId: 'a',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 100,
          note: '',
          loggedAt: DateTime(2026, 10, 12),
          createdAt: DateTime(2026, 10, 12),
        ),
      ],
      month: DateTime(2026, 10),
    );

    test('a frozen copy keeps the numbers it was closed with', () {
      final original = report();
      final closed = ClosedMonth(
        monthKey: ClosedMonth.keyFor(DateTime(2026, 10)),
        closedAt: DateTime(2026, 11, 1),
        reports: {
          'chemical': original.rows.map(ClosedRow.fromReport).toList(),
        },
        events: {'chemical': original.events},
        lowStock: {'chemical': original.lowStockCount},
      );

      // The logs change afterwards — a correction two weeks later.
      final later = buildMonthlyReport(
        kind: ItemKind.chemical,
        chemicals: [
          Chemical(
            id: 'a',
            name: 'Acetone',
            formula: 'C3H6O',
            unit: 'mL',
            quantity: 400,
            initialQuantity: 1000,
            lowStockThreshold: 100,
            notes: '',
            qrCode: '',
            createdAt: DateTime(2026),
          ),
        ],
        apparatus: const [],
        logs: [
          ConsumptionLog(
            id: 'log',
            itemId: 'a',
            itemType: ItemKind.chemical,
            action: InventoryAction.consume,
            amount: 700,
            note: '',
            loggedAt: DateTime(2026, 10, 12),
            createdAt: DateTime(2026, 10, 12),
          ),
        ],
        month: DateTime(2026, 10),
      );

      final frozen = frozenReport(
        closed,
        ItemKind.chemical,
        DateTime(2026, 10),
      );
      expect(later.rows.single.used, 700);
      expect(frozen.rows.single.used, 100, reason: 'the filed number holds');
      expect(frozen.events, original.events);
      expect(frozen.lowStockCount, original.lowStockCount);
    });

    test('a closed month survives a round trip through storage', () {
      final original = report();
      final closed = ClosedMonth(
        monthKey: '2026-10',
        closedAt: DateTime(2026, 11, 1, 9, 30),
        reports: {
          'chemical': original.rows.map(ClosedRow.fromReport).toList(),
        },
        events: {'chemical': 1},
        lowStock: {'chemical': 0},
      );
      final restored = ClosedMonth.fromJson(closed.toJson());
      expect(restored.monthKey, '2026-10');
      expect(restored.closedAt, DateTime(2026, 11, 1, 9, 30));
      expect(restored.reports['chemical']!.single.name, 'Acetone');
      expect(restored.reports['chemical']!.single.left, 400);
      expect(restored.events['chemical'], 1);
    });

    test('the month key is the calendar month, not the day', () {
      expect(ClosedMonth.keyFor(DateTime(2026, 10, 31)), '2026-10');
      expect(ClosedMonth.keyFor(DateTime(2026, 10, 1)), '2026-10');
      expect(ClosedMonth.keyFor(DateTime(2026, 11, 1)), '2026-11');
    });
  });
}
