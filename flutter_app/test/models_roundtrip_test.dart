import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';

Chemical _chemical({
  double quantity = 250,
  double initial = 500,
  double threshold = 100,
}) => Chemical(
  id: 'chem',
  name: 'Hydrochloric acid',
  formula: 'HCl',
  unit: 'mL',
  quantity: quantity,
  initialQuantity: initial,
  lowStockThreshold: threshold,
  notes: '',
  qrCode: 'qr-chem',
  createdAt: DateTime.utc(2026, 3, 4, 9, 30),
);

void main() {
  group('map round trips', () {
    test('a chemical survives toMap/fromMap unchanged', () {
      final chemical = _chemical();
      final restored = Chemical.fromMap(chemical.toMap());

      expect(restored.id, chemical.id);
      expect(restored.name, chemical.name);
      expect(restored.formula, chemical.formula);
      expect(restored.unit, chemical.unit);
      expect(restored.quantity, 250);
      expect(restored.initialQuantity, 500);
      expect(restored.lowStockThreshold, 100);
      expect(restored.qrCode, chemical.qrCode);
      expect(restored.createdAt, chemical.createdAt);
    });

    test('numeric columns sent back as strings or null still parse', () {
      final chemical = Chemical.fromMap({
        'id': 'chem-2',
        'name': 'Ethanol',
        'quantity': '12.5',
        'initial_quantity': '20',
        'low_stock_threshold': null,
      });

      expect(chemical.quantity, 12.5);
      expect(chemical.initialQuantity, 20);
      expect(chemical.lowStockThreshold, 0);
      expect(chemical.unit, 'mL');
      expect(chemical.formula, '');
    });

    test('an apparatus row falls back to the "other" category', () {
      final apparatus = Apparatus.fromMap({'id': 'app-1', 'name': 'Beaker'});

      expect(apparatus.category, 'other');
      expect(apparatus.quantity, 0);
      expect(apparatus.stockState, StockState.empty);
    });

    test('a log keeps its action, item kind and operation id', () {
      final log = ConsumptionLog(
        id: 'log-1',
        itemId: 'chem-1',
        itemType: ItemKind.apparatus,
        action: InventoryAction.breakage,
        amount: 2,
        note: 'dropped',
        loggedAt: DateTime.utc(2026, 3, 4, 12),
        createdAt: DateTime.utc(2026, 3, 4, 12),
        operationId: 'op-1',
      );

      final restored = ConsumptionLog.fromMap(log.toMap());

      expect(restored.itemType, ItemKind.apparatus);
      expect(restored.action, InventoryAction.breakage);
      expect(restored.amount, 2);
      expect(restored.note, 'dropped');
      expect(restored.operationId, 'op-1');
    });

    test('an unknown action degrades to consume instead of throwing', () {
      final log = ConsumptionLog.fromMap({
        'id': 'log-2',
        'item_id': 'chem-1',
        'item_type': 'chemical',
        'action': 'teleported',
        'amount': 1,
      });

      expect(log.action, InventoryAction.consume);
      expect(log.itemType, ItemKind.chemical);
    });
  });

  group('stock progress', () {
    test('always reports a value between 0 and 1', () {
      for (final quantity in [0.0, 1.0, 25.0, 250.0, 500.0, 900.0]) {
        expect(
          _chemical(quantity: quantity).stockProgress,
          inInclusiveRange(0, 1),
        );
      }
    });

    test('an empty item reads as zero and a full one as one', () {
      expect(_chemical(quantity: 0).stockProgress, 0);
      expect(_chemical(quantity: 500).stockProgress, 1);
    });

    test('falls back to the initial quantity when no threshold is set', () {
      expect(_chemical(quantity: 250, threshold: 0).stockProgress, .5);
    });
  });

  group('quantity formatting', () {
    test('drops trailing zeroes but keeps real precision', () {
      expect(formatQuantity(50), '50');
      expect(formatQuantity(12.5), '12.5');
      expect(formatQuantity(12.26), '12.26');
      expect(formatQuantity(0), '0');
    });
  });
}
