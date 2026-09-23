import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/domain/usage_rows.dart';

Chemical _chemical(String id, {required double quantity}) => Chemical(
  id: id,
  name: id,
  formula: 'F',
  unit: 'mL',
  quantity: quantity,
  initialQuantity: 10,
  lowStockThreshold: 0,
  notes: '',
  qrCode: 'q',
  createdAt: DateTime(2026, 1, 1),
);

ConsumptionLog _log(String itemId, InventoryAction action, double amount) =>
    ConsumptionLog(
      id: '$itemId-${action.name}-$amount',
      itemId: itemId,
      itemType: ItemKind.chemical,
      action: action,
      amount: amount,
      note: '',
      loggedAt: DateTime(2026, 9, 2),
      createdAt: DateTime(2026, 9, 2),
    );

void main() {
  test('increase is separate from start stock, and idle items stay out', () {
    final rows = periodUsageRows(
      kind: ItemKind.chemical,
      chemicals: [
        _chemical('used', quantity: 85),
        _chemical('restocked', quantity: 30),
        _chemical('spent', quantity: 7),
        _chemical('idle', quantity: 40),
      ],
      apparatus: const [],
      logsInRange: [
        _log('used', InventoryAction.restock, 20),
        _log('used', InventoryAction.consume, 15),
        _log('restocked', InventoryAction.restock, 10),
        _log('spent', InventoryAction.consume, 3),
      ],
    );

    expect(rows.map((row) => row.id), ['used', 'spent', 'restocked']);
    expect(rows.any((row) => row.restocked > 0), isTrue);

    final used = rows.first;
    expect(used.opening, 80);
    expect(used.restocked, 20);
    expect(used.initial, 100);
    expect(used.used, 15);
    expect(used.finalQuantity, 85);
    expect(used.opening + used.restocked - used.used, used.finalQuantity);

    final spent = rows[1];
    expect(spent.opening, 10);
    expect(spent.restocked, 0);
    expect(spent.initial, spent.opening);
    expect(spent.used, 3);
    expect(spent.finalQuantity, 7);

    final restocked = rows.last;
    expect(restocked.opening, 20);
    expect(restocked.restocked, 10);
    expect(restocked.used, 0);
    expect(restocked.finalQuantity, 30);
    expect(
      restocked.opening + restocked.restocked - restocked.used,
      restocked.finalQuantity,
    );
  });

  test('a period with no restock keeps the original start-stock figure', () {
    final rows = periodUsageRows(
      kind: ItemKind.chemical,
      chemicals: [_chemical('spent', quantity: 7)],
      apparatus: const [],
      logsInRange: [_log('spent', InventoryAction.consume, 3)],
    );

    expect(rows, hasLength(1));
    expect(rows.single.restocked, 0);
    expect(rows.single.opening, 10);
    expect(rows.single.opening - rows.single.used, rows.single.finalQuantity);
  });
}
