import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';

void main() {
  group('inventory domain rules', () {
    test('stock state includes empty and low items', () {
      Chemical chemical(double quantity) => Chemical(
        id: 'id',
        name: 'Hydrochloric acid',
        formula: 'HCl',
        unit: 'mL',
        quantity: quantity,
        initialQuantity: 100,
        lowStockThreshold: 20,
        notes: '',
        qrCode: 'qr',
        createdAt: DateTime(2026),
      );

      expect(chemical(50).stockState, StockState.healthy);
      expect(chemical(20).stockState, StockState.low);
      expect(chemical(0).stockState, StockState.empty);
    });

    test('local day keys use local calendar dates', () {
      final local = DateTime(2026, 9, 18, 12);
      expect(localDayKey(local), '2026-09-18');
      expect(localDayAtNoon(local).hour, 12);
    });

    test('quantity formatting avoids unnecessary decimal zeroes', () {
      expect(formatQuantity(50), '50');
      expect(formatQuantity(12.5), '12.5');
      expect(formatQuantity(12.25), '12.25');
    });
  });
}
