import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/core/theme/app_theme.dart';
import 'package:lab_wizard_v2/core/widgets/jar_metrics.dart';

void main() {
  group('order level not set', () {
    test('stays fine however little is left', () {
      final metrics = jarMetrics(
        quantity: 2,
        initialQuantity: 500,
        threshold: 0,
      );

      expect(metrics.signal, StockSignal.fine);
      expect(metrics.hasLimit, isFalse);
      expect(metrics.notch, isNull);
      // Still honest about the level even though nothing is flagged.
      expect(metrics.fill, closeTo(.004, .001));
      expect(metrics.ticks, 1, reason: 'any liquid earns one tick');
    });

    test('zero is empty even with no level set', () {
      final metrics = jarMetrics(
        quantity: 0,
        initialQuantity: 500,
        threshold: 0,
      );

      expect(metrics.signal, StockSignal.empty);
      expect(metrics.fill, 0);
      expect(metrics.ticks, 0);
    });

    test('the caption nudges without warning', () {
      final metrics = jarMetrics(
        quantity: 400,
        initialQuantity: 500,
        threshold: 0,
      );

      expect(stockCaption(metrics, piecewiseUnit: false), 'set limit');
      // Apparatus has no threshold habit, so it never nags.
      expect(stockCaption(metrics, piecewiseUnit: true), '');
    });
  });

  group('order level set', () {
    test('flags only once stock reaches the level', () {
      JarMetrics at(double quantity) => jarMetrics(
        quantity: quantity,
        initialQuantity: 500,
        threshold: 300,
      );

      expect(at(400).signal, StockSignal.fine);
      expect(at(300).signal, StockSignal.order);
      expect(at(120).signal, StockSignal.order);
      expect(at(0).signal, StockSignal.empty);
    });

    test('the notch sits where the level begins', () {
      final metrics = jarMetrics(
        quantity: 250,
        initialQuantity: 500,
        threshold: 300,
      );

      expect(metrics.notch, closeTo(.6, .001));
      // A jar can be over half full and still need ordering. That is the point.
      expect(metrics.fill, closeTo(.5, .001));
      expect(metrics.signal, StockSignal.order);
      expect(stockCaption(metrics, piecewiseUnit: false), 'order');
    });

    test('a level above the jar pins the notch to the top', () {
      final metrics = jarMetrics(
        quantity: 450,
        initialQuantity: 500,
        threshold: 600,
      );

      expect(metrics.notch, 1);
      expect(metrics.signal, StockSignal.order);
    });
  });

  group('capacity', () {
    test('restocking past the original size fills rather than overflows', () {
      final metrics = jarMetrics(
        quantity: 800,
        initialQuantity: 500,
        threshold: 100,
      );

      expect(metrics.fill, 1);
      expect(metrics.ticks, 5);
    });

    test('a record with no initial quantity reads full, not inventing a level',
        () {
      final metrics = jarMetrics(
        quantity: 50,
        initialQuantity: 0,
        threshold: 0,
      );

      expect(metrics.fill, 1);
      expect(metrics.ticks, 5);
    });

    test('nonsense values do not throw', () {
      final metrics = jarMetrics(
        quantity: double.nan,
        initialQuantity: -5,
        threshold: double.infinity,
      );

      expect(metrics.fill, 0);
      expect(metrics.signal, StockSignal.empty);
    });
  });

  group('ticks', () {
    test('round down so nearly full never reads as full', () {
      int ticksAt(double fill) =>
          jarMetrics(quantity: 500 * fill, initialQuantity: 500, threshold: 0)
              .ticks;

      expect(ticksAt(1), 5);
      expect(ticksAt(.9), 4);
      expect(ticksAt(.79), 3);
      expect(ticksAt(.41), 2);
      expect(ticksAt(.2), 1);
    });

    test('whole pieces tick one unit each', () {
      int pieces(double quantity) => jarMetrics(
        quantity: quantity,
        initialQuantity: 5,
        threshold: 0,
        piecewise: true,
      ).ticks;

      expect(pieces(3), 3);
      expect(pieces(1), 1);
      expect(pieces(0), 0);
    });
  });
}
