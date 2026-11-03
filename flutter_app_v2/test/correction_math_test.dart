import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/inventory/domain/models.dart';

/// The arithmetic behind "fix that entry". It lives in the domain files so the
/// repository and the tests cannot drift apart.
void main() {
  group('correcting a logged entry', () {
    test('a smaller amount puts the difference back on the shelf', () {
      // 500 g was logged as used, but only 50 g went: 450 g returns.
      final after = _corrected(
        currentQuantity: 500,
        oldAction: InventoryAction.consume,
        oldAmount: 500,
        newAction: InventoryAction.consume,
        newAmount: 50,
      );
      expect(after, 950);
    });

    test('a bigger amount takes the difference off', () {
      final after = _corrected(
        currentQuantity: 900,
        oldAction: InventoryAction.consume,
        oldAmount: 100,
        newAction: InventoryAction.consume,
        newAmount: 250,
      );
      expect(after, 750);
    });

    test('changing use into a restock flips the direction', () {
      final after = _corrected(
        currentQuantity: 400,
        oldAction: InventoryAction.consume,
        oldAmount: 100,
        newAction: InventoryAction.restock,
        newAmount: 100,
      );
      expect(after, 600);
    });

    test('changing a restock into use flips it back', () {
      final after = _corrected(
        currentQuantity: 600,
        oldAction: InventoryAction.restock,
        oldAmount: 100,
        newAction: InventoryAction.consume,
        newAmount: 100,
      );
      expect(after, 400);
    });

    test('correcting the amount does not need the action to change', () {
      final after = _corrected(
        currentQuantity: 10,
        oldAction: InventoryAction.breakage,
        oldAmount: 3,
        newAction: InventoryAction.breakage,
        newAmount: 5,
      );
      // 13 before it broke, 8 after five broke instead of three.
      expect(after, 8);
    });

    test('a correction never leaves the shelf below zero', () {
      final after = _corrected(
        currentQuantity: 10,
        oldAction: InventoryAction.restock,
        oldAmount: 100,
        newAction: InventoryAction.consume,
        newAmount: 500,
      );
      expect(after, 0);
    });

    test('an unchanged entry leaves the quantity exactly as it was', () {
      for (final action in InventoryAction.values) {
        final after = _corrected(
          currentQuantity: 42,
          oldAction: action,
          oldAmount: 7,
          newAction: action,
          newAmount: 7,
        );
        expect(after, 42, reason: 'unchanged $action should be a no-op');
      }
    });

    test('removing an entry is the same as winding it back', () {
      final after = _corrected(
        currentQuantity: 300,
        oldAction: InventoryAction.consume,
        oldAmount: 200,
        newAction: InventoryAction.restock,
        newAmount: 0,
      );
      // Removing a 200 use = adding nothing to a shelf of 500.
      expect(after, 500);
    });
  });
}

/// Shorthand so each case reads as one thought.
double _corrected({
  required double currentQuantity,
  required InventoryAction oldAction,
  required double oldAmount,
  required InventoryAction newAction,
  required double newAmount,
}) => quantityAfterCorrection(
  currentQuantity: currentQuantity,
  oldAction: oldAction,
  oldAmount: oldAmount,
  newAction: newAction,
  newAmount: newAmount,
);
