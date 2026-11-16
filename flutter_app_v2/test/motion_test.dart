import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/core/motion.dart';

void main() {
  group('rockWave — the vessel body moving', () {
    test('is exactly zero at rest at both ends', () {
      // A vessel left fractionally tilted is a vessel claiming the floor slopes.
      // "Close to zero" is not good enough: it has to be zero, because the
      // painter adds this value to the surface and nothing clamps it afterwards.
      expect(LabMotion.rockWave(0), 0);
      expect(LabMotion.rockWave(1), 0);
      expect(LabMotion.rockWave(-.2), 0, reason: 'never extrapolate');
      expect(LabMotion.rockWave(1.4), 0);
    });

    test('peaks early, then settles', () {
      // A rock that wound up slowly would read as an animation starting rather
      // than as a shove. The loudest moment should be in the first third.
      var peak = 0.0;
      var peakAt = 0.0;
      for (var i = 1; i < 100; i++) {
        final t = i / 100;
        final value = LabMotion.rockWave(t).abs();
        if (value > peak) {
          peak = value;
          peakAt = t;
        }
      }
      expect(peakAt, lessThan(.4));
      expect(peak, greaterThan(.4), reason: 'it has to be visible');
    });

    test('rebounds the other way, so it reads as liquid not as a dip', () {
      // One half-cycle would be a dip. A real vessel rocks past level and back.
      final first = LabMotion.rockWave(.2);
      final later = [
        for (var i = 45; i < 75; i++) LabMotion.rockWave(i / 100),
      ];
      expect(first, greaterThan(0));
      expect(
        later.any((v) => v < -.02),
        isTrue,
        reason: 'there must be a rebound below level',
      );
    });

    test('is bounded by the vessel body, never by a runaway envelope', () {
      for (var i = 0; i <= 200; i++) {
        final value = LabMotion.rockWave(i / 200);
        expect(value.abs(), lessThanOrEqualTo(1.0));
        expect(value.isFinite, isTrue);
      }
    });

    test('keeps decaying: the second half is quieter than the first', () {
      double total(int from, int to) {
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          sum += LabMotion.rockWave(i / 200).abs();
        }
        return sum;
      }

      expect(total(100, 200), lessThan(total(0, 100)));
    });
  });

  group('settleWave — the ripples', () {
    test('is exactly zero at rest at both ends', () {
      expect(LabMotion.settleWave(0), 0);
      expect(LabMotion.settleWave(1), 0);
    });

    test('stays inside the surface it is drawn on', () {
      for (var i = 0; i <= 200; i++) {
        final value = LabMotion.settleWave(i / 200);
        expect(value.abs(), lessThanOrEqualTo(1.5));
      }
    });
  });

  group('the two curves are different motions', () {
    test('the rock is slower than the ripple', () {
      // Count sign changes: ripples cross level far more often than a body
      // rock should. If these two ever converge, the pour loses its weight.
      int crossings(double Function(double) f) {
        var count = 0;
        var previous = f(.01);
        for (var i = 2; i < 100; i++) {
          final value = f(i / 100);
          if (previous.sign != value.sign && value != 0) count++;
          previous = value;
        }
        return count;
      }

      expect(crossings(LabMotion.settleWave), greaterThan(crossings(LabMotion.rockWave)));
    });

    test('both are safe to sample at the exact endpoints', () {
      // The controllers hand the painter t == 0 and t == 1 at rest.
      for (final t in [0.0, 1.0]) {
        expect(LabMotion.rockWave(t), 0);
        expect(LabMotion.settleWave(t), 0);
        expect(math.sin(math.pi * t), closeTo(0, 1e-12));
      }
    });
  });
}
