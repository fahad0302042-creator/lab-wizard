import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/core/widgets/vessel_level.dart';

/// The angle a phone actually produces, after the per-vessel exaggeration the
/// shelf rows and the dashboard hero apply.
double _tip(double phoneDegrees, double sensitivity) =>
    phoneDegrees * sensitivity * math.pi / 180;

void main() {
  group('the liquid surface stays visible', () {
    test('an upright vessel keeps its exact fill', () {
      expect(
        ensureVisibleFill(
          fill: .24,
          tipRadians: 0,
          bodyWidth: 30,
          bodyHeight: 34,
          waveFraction: .085,
        ),
        .24,
      );
    });

    test('every drawable fill is drawn at some lean, for every proportion', () {
      // The vessel must never render as a sealed, full body: whatever it holds,
      // the surface has to be able to reach the walls. Violating this is what
      // produced "the liquid is not moving".
      const shapes = [
        (12.0, 44.0), // tall test tube
        (30.0, 34.0), // shelf-row bottle
        (112.0, 131.0), // dashboard hero
        (60.0, 20.0), // wide, shallow
      ];
      for (final (w, h) in shapes) {
        for (final deg in [0.0, 10.0, 20.0, 30.0, 42.0]) {
          for (final sens in [1.0, 1.5, 1.8]) {
            final tip = _tip(deg, sens);
            for (final fill in [.02, .08, .24, .5, .82, .98]) {
              final drawn = ensureVisibleFill(
                fill: fill,
                tipRadians: tip,
                bodyWidth: w,
                bodyHeight: h,
                waveFraction: .085,
              );
              expect(
                drawn,
                inInclusiveRange(0.0, 1.0),
                reason: '$w x $h at $deg deg (x$sens), fill $fill',
              );
            }
          }
        }
      }
    });

    test('never hands clamp an inverted range', () {
      // A previous revision derived the band from the half-diagonal; on a wide
      // body the lower bound overtook the upper one, and `clamp` asserts when
      // lower > upper. Exercise the widest body at the hardest lean.
      expect(
        () => ensureVisibleFill(
          fill: .5,
          tipRadians: _tip(42, 1.8),
          bodyWidth: 112,
          bodyHeight: 131,
          waveFraction: .085,
        ),
        returnsNormally,
      );
    });

    test('a wide vessel is left unclamped, because its surface always shows', () {
      final drawn = ensureVisibleFill(
        fill: .24,
        tipRadians: _tip(42, 1.8),
        bodyWidth: 112,
        bodyHeight: 131,
        waveFraction: .085,
      );
      expect(drawn, .24);
    });

    test('a long narrow tube lifts a shallow fill, but only just', () {
      // 12x44 is the only shape here narrow enough for the band to bind, and it
      // only starts binding near 35 degrees of phone tilt. The lift must stay
      // small: the drawn height is still supposed to carry the quantity.
      final upright = ensureVisibleFill(
        fill: .02,
        tipRadians: 0,
        bodyWidth: 12,
        bodyHeight: 44,
        waveFraction: .085,
      );
      final leaned = ensureVisibleFill(
        fill: .02,
        tipRadians: _tip(42, 1.5),
        bodyWidth: 12,
        bodyHeight: 44,
        waveFraction: .085,
      );
      expect(upright, .02);
      expect(leaned, greaterThan(upright));
      expect(leaned, lessThan(.2), reason: 'a lift, not a rewrite');
    });

    test('the lift is monotonic: more lean never lowers the floor', () {
      double floorAt(double deg) => ensureVisibleFill(
        fill: 0,
        tipRadians: _tip(deg, 1.5),
        bodyWidth: 8,
        bodyHeight: 88,
        waveFraction: 0,
      );

      var previous = floorAt(0);
      for (final deg in [10.0, 20.0, 30.0, 42.0]) {
        final next = floorAt(deg);
        expect(next, greaterThanOrEqualTo(previous));
        previous = next;
      }
      // A test tube lying nearly on its side cannot show an empty sliver: the
      // surface would sit outside the glass. A fifth of the body is the floor.
      expect(previous, greaterThan(.2));
      expect(previous, lessThan(.5));
    });

    test('a half-full vessel is always drawable, at any lean', () {
      // The band is symmetric about the middle, so this is the strongest
      // guarantee the helper can offer and the one worth holding onto.
      for (final (w, h) in [(8.0, 88.0), (12.0, 44.0), (30.0, 34.0)]) {
        for (final deg in [0.0, 15.0, 30.0, 42.0]) {
          expect(
            ensureVisibleFill(
              fill: .5,
              tipRadians: _tip(deg, 1.8),
              bodyWidth: w,
              bodyHeight: h,
            ),
            .5,
            reason: '$w x $h at $deg deg',
          );
        }
      }
    });

    test('degenerate geometry is passed through, not crashed on', () {
      expect(
        ensureVisibleFill(
          fill: .4,
          tipRadians: 0,
          bodyWidth: 0,
          bodyHeight: 0,
        ),
        .4,
      );
    });
  });
}
