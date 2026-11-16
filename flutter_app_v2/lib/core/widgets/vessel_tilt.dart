import 'package:flutter/widgets.dart';

import '../motion.dart';
import 'glass_jar.dart';
import 'jar_metrics.dart';

/// Feeds every [Vessel] below it the lean it should draw.
///
/// There used to be a gyroscope here. It was removed, and it is worth recording
/// why, because "add a sensor" looks like a good idea twice a year:
///
/// **The gyro only moved when you tilted the phone** — which is the moment you
/// are *not* reading the app. It never asked to be tilted, so it animated in
/// demos and did nothing in use. That is the definition of a decoration, and a
/// decoration on a stock ledger makes the ledger feel like a toy.
///
/// What replaced it is a lean driven by things that actually happen: a thumb
/// dragging a vessel, and [LeanScope.pour] when stock is logged. The animation
/// still exists; it is now attached to the user's own hands.
///
/// The three structural decisions survived the change and still matter:
///
/// 1. **One notifier for the whole app.** A shelf can hold forty vessels; forty
///    independent animations would be forty controllers. The lean is one
///    shared notifier, however many vessels are on screen.
/// 2. **A lean change never rebuilds a screen.** The value lives in an
///    [InheritedNotifier]; a *vessel* depends on it, so a lean repaints vessels
///    and nothing else. `ref.watch` here would rebuild lists and headers for a
///    decoration.
/// 3. **It claims no gestures.** The drag that leans a vessel lives on the
///    vessel itself. Wrapping a screen in a horizontal drag recogniser would
///    have it compete with swipe-to-panel and vertical scroll for every touch.
class LeanScope extends StatefulWidget {
  const LeanScope({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// False when the user asked for reduced motion. The scope then publishes
  /// zero and stays out of the way.
  final bool enabled;

  @override
  State<LeanScope> createState() => _LeanScopeState();
}

class _LeanScopeState extends State<LeanScope>
    with SingleTickerProviderStateMixin {
  late final _LeanModel _model = _LeanModel(vsync: this);

  @override
  void didUpdateWidget(covariant LeanScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled && !widget.enabled) {
      _model.leanNow(0);
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LeanScopeBox(model: _model, child: widget.child);
}

/// Publishes the current lean to every vessel below it.
class _LeanScopeBox extends InheritedNotifier<_LeanModel> {
  const _LeanScopeBox({required _LeanModel model, required super.child})
    : super(notifier: model);
}

class _LeanModel extends ChangeNotifier {
  _LeanModel({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: LabMotion.tiltFollow,
      ) {
    _controller.addListener(() {
      lean = _from + (_to - _from) * Curves.easeOut.transform(_controller.value);
      notifyListeners();
    });
  }

  final AnimationController _controller;
  double _from = 0;
  double _to = 0;

  /// The lean the vessels should draw, in degrees, clamped so a full twist
  /// cannot turn a jar upside down.
  double lean = 0;

  /// Where the liquid returns to when a thumb lets go. Zero, because nothing
  /// else is pushing the vessel around any more.
  static const double _rest = 0;

  /// Eases to [target]. A fresh target mid-flight restarts from wherever the
  /// glass currently is, so a fast movement never makes the liquid jump.
  void animateTo(double target) {
    final clamped = target.clamp(-46.0, 46.0);
    if ((clamped - _to).abs() < .05) return;
    _from = lean;
    _to = clamped;
    _controller
      ..reset()
      ..forward();
  }

  /// A thumb's lean, applied immediately.
  void setLean(double value) {
    final clamped = value.clamp(-46.0, 46.0);
    _from = clamped;
    _to = clamped;
    lean = clamped;
    notifyListeners();
  }

  /// Returns to rest after a thumb lets go.
  void settle() {
    _from = lean;
    _to = _rest;
    _controller
      ..reset()
      ..forward();
  }

  /// Jumps, for the cases where easing would be a lie: reduced motion, or the
  /// lean being switched off.
  void leanNow(double value) {
    _controller.stop();
    _from = value;
    _to = value;
    lean = value;
    notifyListeners();
  }
}

/// Drives the vessel that belongs to an item, from anywhere on the screen.
///
/// Logging stock happens in a sheet, an undo bar, or a scan; the vessel being
/// changed may be scrolled off screen or may not exist yet. Rather than thread a
/// callback through every one of those paths, the event is broadcast: whoever is
/// showing that item's vessel picks it up. Nothing else in the tree hears it.
abstract final class Lean {
  const Lean._();

  /// Adds a thumb's movement to the current lean.
  ///
  /// `getInheritedWidgetOfExactType` rather than `dependOn…`: this runs inside a
  /// gesture callback, so there is nothing to rebuild — the model notifies the
  /// vessels itself.
  static void nudge(BuildContext context, double dx) {
    final model = context.getInheritedWidgetOfExactType<_LeanScopeBox>()?.notifier;
    if (model == null) return;
    model.setLean((model.lean + dx * .5).clamp(-46.0, 46.0));
  }

  /// Lets go: the liquid finds its level again.
  static void release(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LeanScopeBox>()?.notifier?.settle();
}

/// A [Vessel] that can be leaned by thumb.
///
/// Without an enclosing [LeanScope] it simply sits flat — what tests, desktop
/// and the web preview get. [sensitivity] exaggerates the lean for small
/// vessels: at 22×28 dp a 40° lean moves the surface less than a pixel. The
/// exaggeration is constant, so the liquid still tips the same way at the same
/// time; it is scale, not fiction.
///
/// Dragging *this widget* leans the liquid. The horizontal drag is claimed only
/// when the touch lands on the vessel, and Flutter's gesture arena then decides
/// between it, the row's swipe and the list's scroll — so a thumb that starts
/// on a bottle tips it, and a thumb that starts anywhere else scrolls normally.
/// On release the liquid finds its own level again, which is what a real vessel
/// does and what makes the gesture read as physics rather than a slider.
class LeaningVessel extends StatefulWidget {
  const LeaningVessel({
    required this.metrics,
    this.width = 34,
    this.height = 42,
    this.onTap,
    this.semanticLabel,
    this.sensitivity = 1,
    this.shape = VesselShape.bottle,
    this.pouredAt,
    super.key,
  });

  final JarMetrics metrics;
  final double width;
  final double height;

  /// A bottle for reagents, a beaker for apparatus.
  final VesselShape shape;

  /// Passed straight through to the painter's swing trigger; see
  /// `Vessel.pouredAt`.
  final DateTime? pouredAt;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double sensitivity;

  @override
  State<LeaningVessel> createState() => _LeaningVesselState();
}

class _LeaningVesselState extends State<LeaningVessel> {
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_LeanScopeBox>();
    final lean = scope?.notifier?.lean ?? 0;

    return RepaintBoundary(
      child: GestureDetector(
        // A drag that starts directly on the vessel is unambiguous: nothing else
        // on a shelf wants a horizontal drag from exactly there.
        onHorizontalDragUpdate: (details) =>
            Lean.nudge(context, details.delta.dx),
        onHorizontalDragEnd: (_) => Lean.release(context),
        onHorizontalDragCancel: () => Lean.release(context),
        child: Vessel(
          metrics: widget.metrics,
          width: widget.width,
          height: widget.height,
          shape: widget.shape,
          onTap: widget.onTap,
          semanticLabel: widget.semanticLabel,
          tiltSensitivity: widget.sensitivity,
          tipDegrees: lean,
          pouredAt: widget.pouredAt,
        ),
      ),
    );
  }
}

/// The live lean, as a widget that rebuilds *only itself*.
///
/// Used by the dashboard hero's painter, so the glass leans without dragging the
/// rest of the screen into a rebuild.
class TiltReadout extends StatelessWidget {
  const TiltReadout({required this.builder, super.key});

  final Widget Function(BuildContext context, double lean) builder;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_LeanScopeBox>();
    return builder(context, scope?.notifier?.lean ?? 0);
  }
}
