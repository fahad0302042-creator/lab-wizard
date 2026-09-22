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
  test('restock raises initial as well as final, and unused items stay out', () {
    final rows = periodUsageRows(
      kind: ItemKind.chemical,
      chemicals: [
        _chemical('used', quantity: 85),
        _chemical('restocked', quantity: 30),
        _chemical('idle', quantity: 40),
      ],
      apparatus: const [],
      logsInRange: [
        _log('used', InventoryAction.restock, 20),
        _log('used', InventoryAction.consume, 15),
        _log('restocked', InventoryAction.restock, 10),
      ],
    );

    expect(rows.map((row) => row.id), ['used', 'restocked']);

    final used = rows.first;
    expect(used.initial, 100);
    expect(used.restocked, 20);
    expect(used.used, 15);
    expect(used.finalQuantity, 85);
    expect(used.initial - used.used, used.finalQuantity);

    final restocked = rows.last;
    expect(restocked.initial, 30);
    expect(restocked.restocked, 10);
    expect(restocked.used, 0);
    expect(restocked.finalQuantity, 30);
  });
}
