import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion.dart';
import '../tilt/tilt_providers.dart';
import '../tilt/tilt_source.dart';
import 'glass_jar.dart';
import 'jar_metrics.dart';

/// Feeds every [Vessel] below it the phone's tilt.
///
/// Three decisions matter here, and they are all about what the gyro is *not*
/// allowed to do:
///
/// 1. **One subscription for the whole app.** A shelf can hold forty vessels
///    and forty subscriptions would mean forty identical platform streams. The
///    sensor, the Kotlin filter and the channel work are paid once, in
///    [HomeShell], no matter how many rows are on screen.
/// 2. **A gyro sample never rebuilds a screen.** The reading is written into an
///    [InheritedNotifier]; a *vessel* depends on that notifier, so a sample
///    repaints vessels and nothing else. Subscribing through `ref.watch` here
///    would rebuild the list, the headers and the text thirty times a second,
///    on a midrange phone, for a decoration.
/// 3. **It claims no gestures.** The drag that leans the liquid lives on the
///    vessel (`LeaningVessel`), not on this wrapper. Wrapping a whole screen in
///    a horizontal drag recogniser would have it compete with the shelf's
///    swipe-to-panel and its vertical scroll for every touch — and a wrapper
///    that eats swipes to serve a decoration is a bad trade.
class VesselTilt extends ConsumerStatefulWidget {
  const VesselTilt({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// False when the user switched tilt off or asked for reduced motion. The
  /// scope then publishes zero and stays out of the way.
  final bool enabled;

  @override
  ConsumerState<VesselTilt> createState() => _VesselTiltState();
}

class _VesselTiltState extends ConsumerState<VesselTilt>
    with SingleTickerProviderStateMixin {
  late final _TiltModel _model = _TiltModel(vsync: this);

  /// What the sensor is asking for.
  double _sensorTip = 0;

  @override
  void initState() {
    super.initState();
    // A plain listen, not watch: samples must not rebuild this widget or its
    // subtree. Only the model — and therefore only the vessels that depend on
    // it — hears about them.
    ref.listenManual<AsyncValue<TiltReading>>(tiltProvider, (previous, next) {
      final reading = next.valueOrNull;
      if (reading == null) return;
      if (!reading.supported || !widget.enabled) {
        _sensorTip = 0;
      } else if (!reading.flat) {
        // `flat` means the reading is noise; hold the last lean instead of
        // chasing the jitter, so a phone lying on a bench looks still.
        _sensorTip = reading.tipDegrees;
      }
      _apply();
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(covariant VesselTilt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _apply();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _apply() {
    if (!widget.enabled || LabMotion.reduced(context)) {
      _model.leanNow(0);
      return;
    }
    _model.animateTo(_sensorTip);
  }

  @override
  Widget build(BuildContext context) => _TiltScope(model: _model, child: widget.child);
}

/// Publishes the current lean to every vessel below it.
class _TiltScope extends InheritedNotifier<_TiltModel> {
  const _TiltScope({required _TiltModel model, required super.child})
    : super(notifier: model);
}

class _TiltModel extends ChangeNotifier {
  _TiltModel({required TickerProvider vsync})
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

  /// What the phone alone is asking for. A thumb is added on top of it, and
  /// releasing returns here rather than to zero — otherwise letting go of a
  /// bottle while the phone is still tipped would snap the liquid flat.
  double _sensorTarget = 0;

  /// Eases to [target]. A fresh target mid-flight restarts from wherever the
  /// glass currently is, so a fast wrist movement never makes the liquid jump.
  void animateTo(double target) {
    final clamped = target.clamp(-46.0, 46.0);
    _sensorTarget = clamped;
    if ((clamped - _to).abs() < .05) return;
    _from = lean;
    _to = clamped;
    _controller
      ..reset()
      ..forward();
  }

  /// Returns to the sensor's lean after a thumb lets go.
  void settle() {
    _from = lean;
    _to = _sensorTarget;
    _controller
      ..reset()
      ..forward();
  }

  /// Jumps, for the cases where easing would be a lie: reduced motion, or tilt
  /// being switched off.
  void leanNow(double value) {
    _sensorTarget = value;
    _controller.stop();
    _from = value;
    _to = value;
    lean = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// A [Vessel] that leans with the phone and can be leaned by thumb.
///
/// Without an enclosing [VesselTilt] it simply sits flat — what tests, desktop
/// and the web preview get. [sensitivity] exaggerates the lean for small
/// vessels: at 22×28 dp a 40° tilt moves the surface less than a pixel. The
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
    super.key,
  });

  final JarMetrics metrics;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double sensitivity;

  @override
  State<LeaningVessel> createState() => _LeaningVesselState();
}

class _LeaningVesselState extends State<LeaningVessel> {
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TiltScope>();
    final lean = scope?.notifier?.lean ?? 0;

    return RepaintBoundary(
      child: GestureDetector(
        // A drag that starts directly on the vessel is unambiguous: nothing else
        // on a shelf wants a horizontal drag from exactly there.
        onHorizontalDragUpdate: (details) =>
            TiltNudge.handle(context, details.delta.dx),
        onHorizontalDragEnd: (_) => TiltNudge.release(context),
        onHorizontalDragCancel: () => TiltNudge.release(context),
        child: Vessel(
          metrics: widget.metrics,
          width: widget.width,
          height: widget.height,
          onTap: widget.onTap,
          semanticLabel: widget.semanticLabel,
          tiltSensitivity: widget.sensitivity,
          tipDegrees: lean,
        ),
      ),
    );
  }
}

/// A hard, immediate set used by the drag. Kept on the model so the lean has a
/// single owner and a single clamp.
extension on _TiltModel {
  /// A thumb's lean. Deliberately does not touch [_sensorTarget]: releasing must
  /// settle back to what the phone is doing, not to flat.
  void setLean(double value) {
    final clamped = value.clamp(-46.0, 46.0);
    _from = clamped;
    _to = clamped;
    lean = clamped;
    notifyListeners();
  }
}

/// The drag half of the lean, shared by [LeaningVessel] and any bespoke
/// painted vessel (the dashboard hero has its own painter, but it must lean by
/// thumb exactly like every other one).
abstract final class TiltNudge {
  /// Adds a thumb's movement to the current lean. `getInheritedWidgetOfExactType`
  /// rather than `dependOn…`: this runs inside a gesture callback, so there is
  /// nothing to rebuild — the model notifies the vessels itself.
  static void handle(BuildContext context, double dx) {
    final model = context
        .getInheritedWidgetOfExactType<_TiltScope>()
        ?.notifier;
    if (model == null) return;
    model.setLean((model.lean + dx * .5).clamp(-46.0, 46.0));
  }

  /// Lets go: the liquid finds its level again, at whatever the phone is doing.
  static void release(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_TiltScope>()?.notifier?.settle();
}

/// The live lean, as a widget that rebuilds *only itself* when the phone moves.
///
/// Used by the dashboard hero's readout and by the hero's painter, so the glass
/// leans and the degrees stay honest without dragging the rest of the screen
/// into a 30 Hz rebuild.
class TiltReadout extends StatelessWidget {
  const TiltReadout({required this.builder, super.key});

  final Widget Function(BuildContext context, double lean) builder;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TiltScope>();
    return builder(context, scope?.notifier?.lean ?? 0);
  }
}
