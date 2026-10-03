import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A short settle past the target. Smaller than [Curves.easeOutBack] so a
/// tall sheet does not leap up the screen, but still lands with a spring.
const Curve labSpring = Cubic(0.22, 1.12, 0.32, 1);

/// Counts open sheets so the page under them can scale. The sheet is a new
/// route above this widget, so scaling here does not scale the sheet.
class SheetStageController extends ChangeNotifier {
  int _depth = 0;
  bool _disposed = false;

  bool get isOpen => _depth > 0;

  void begin() {
    if (_disposed) return;
    _depth++;
    notifyListeners();
  }

  void end() {
    if (_disposed || _depth == 0) return;
    _depth--;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SheetStage extends StatefulWidget {
  const SheetStage({required this.child, super.key});

  final Widget child;

  static SheetStageController? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_SheetStageScope>()?.notifier;
  }

  @override
  State<SheetStage> createState() => _SheetStageState();
}

class _SheetStageState extends State<SheetStage> {
  final SheetStageController _controller = SheetStageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetStageScope(
      notifier: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final reduce = MediaQuery.disableAnimationsOf(context);
          final open = _controller.isOpen && !reduce;
          return AnimatedScale(
            scale: open ? 0.97 : 1,
            alignment: Alignment.topCenter,
            duration: context.motion(
              open
                  ? const Duration(milliseconds: 420)
                  : const Duration(milliseconds: 260),
            ),
            curve: labSpring,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _SheetStageScope extends InheritedNotifier<SheetStageController> {
  const _SheetStageScope({required super.notifier, required super.child});
}

/// Springs a sheet up. The modal barrier dims the page; [SheetStage] scales
/// the page behind it, then both return together when the sheet closes.
Future<T?> showLabSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
}) async {
  final reduce = MediaQuery.disableAnimationsOf(context);
  final stage = SheetStage.maybeOf(context);
  stage?.begin();
  try {
    return await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor,
      sheetAnimationStyle: reduce
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 420),
              reverseDuration: Duration(milliseconds: 260),
              curve: labSpring,
              reverseCurve: Curves.easeInCubic,
            ),
      builder: builder,
    );
  } finally {
    stage?.end();
  }
}

/// A chip flies from [context] (the pressed button) to [destination], then
/// completes so the quantity can tick. Instant, and skipped, when motion is
/// reduced. Coordinates are global; the chip is painted on the root overlay
/// so a closing sheet does not clip it.
Future<void> flyActionChip({
  required BuildContext context,
  required String label,
  required GlobalKey destination,
}) async {
  if (!context.mounted || MediaQuery.disableAnimationsOf(context)) return;
  final from = _boxCenter(context);
  final target = destination.currentContext;
  final to = target == null ? null : _boxCenter(target);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (from == null || to == null || overlay == null) return;

  final done = Completer<void>();
  late OverlayEntry entry;
  var finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    if (!done.isCompleted) done.complete();
  }

  entry = OverlayEntry(
    builder: (context) => _FlyingChip(
      label: label,
      from: from,
      to: to,
      onFinished: finish,
      onLanded: () {
        finish();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (entry.mounted) entry.remove();
        });
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

Offset? _boxCenter(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(box.size.center(Offset.zero));
}

class _FlyingChip extends StatefulWidget {
  const _FlyingChip({
    required this.label,
    required this.from,
    required this.to,
    required this.onFinished,
    required this.onLanded,
  });

  final String label;
  final Offset from;
  final Offset to;
  final VoidCallback onFinished;
  final VoidCallback onLanded;

  @override
  State<_FlyingChip> createState() => _FlyingChipState();
}

class _FlyingChipState extends State<_FlyingChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 380),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onLanded();
        });
    _controller.forward();
  }

  @override
  void dispose() {
    final completed = _controller.status == AnimationStatus.completed;
    _controller.dispose();
    if (!completed) widget.onFinished();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeInOutCubic.transform(_controller.value);
            final position = Offset.lerp(widget.from, widget.to, t)!;
            final lift = 32 * math.sin(t * math.pi);
            return Stack(
              children: [
                Positioned(
                  left: position.dx - 16,
                  top: position.dy - lift - 12,
                  child: Opacity(
                    opacity: (1 - t * 0.2).clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              ],
            );
          },
          child: ExcludeSemantics(
            child: Material(
              color: context.inkColor,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: context.paperColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring draws itself and a check lands in the middle. Played once when a
/// scan matches. It fades out at the end so a sitting screen has no loop.
class ScanBurst extends StatefulWidget {
  const ScanBurst({required this.token, super.key});

  final int token;

  @override
  State<ScanBurst> createState() => _ScanBurstState();
}

class _ScanBurstState extends State<ScanBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
  }

  @override
  void didUpdateWidget(ScanBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token == oldWidget.token || widget.token <= 0) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.value == 0) return const SizedBox.shrink();
          return CustomPaint(
            painter: _BurstPainter(
              progress: _controller.value,
              color: Colors.white,
            ),
          );
        },
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final fade = progress < 0.72 ? 1.0 : (1 - (progress - 0.72) / 0.28);
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: fade.clamp(0.0, 1.0));
    final radius = 28 + 16 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.2,
      6.2 * Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0)),
      false,
      ring,
    );
    if (progress < 0.32) return;
    final check = ((progress - 0.32) / 0.36).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: fade.clamp(0.0, 1.0));
    final path = Path()
      ..moveTo(center.dx - 10, center.dy + 1)
      ..lineTo(center.dx - 2, center.dy + 9)
      ..lineTo(center.dx + 12, center.dy - 8);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    canvas.drawPath(
      metrics.first.extractPath(0, metrics.first.length * check),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
