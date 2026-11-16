import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/app_theme.dart';

/// The moment after a log lands.
///
/// Before this existed, logging a session ended in a haptic tick and the sheet
/// closing. Nothing on screen said the record had just become more accurate, so
/// the work of keeping the ledger felt like filling in a form — which is exactly
/// the point at which people stop bothering.
///
/// This is not a reward burst. A lab ledger earns trust by being precise, so the
/// confirmation is the instrument's own language: a scan line sweeps the panel,
/// the item is named, and the level change is stated in the same mono figures
/// the shelf uses. It lasts [LabMotion.standard] and then gets out of the way.
///
/// Drawn on the [Overlay], deliberately **not** as a dialog.
///
/// A dialog would be wrong twice over. It pushes a route, and stock is usually
/// logged from inside a sheet that is closing at that exact moment — pushing a
/// route mid-pop throws. And its barrier absorbs touches for the whole
/// animation, which is unacceptable when someone is logging five items in a row
/// during a lesson. The plate is feedback, so it must not take the screen
/// hostage: it sits on top, ignores every pointer, and removes itself.
void showLogConfirm(
  BuildContext context, {
  required String name,
  required String detail,
  required StockSignal signal,
  required bool rising,
}) {
  if (LabMotion.reduced(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LogConfirm(
      name: name,
      detail: detail,
      signal: signal,
      rising: rising,
      onDone: () {
        // `mounted` before removing: the controller can complete during a
        // teardown, and removing an entry that is already gone throws.
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _LogConfirm extends StatefulWidget {
  const _LogConfirm({
    required this.name,
    required this.detail,
    required this.signal,
    required this.rising,
    required this.onDone,
  });

  final String name;
  final String detail;
  final StockSignal signal;
  final bool rising;

  /// Called once the animation has finished, so the overlay entry can remove
  /// itself. No route, no future to await.
  final VoidCallback onDone;

  @override
  State<_LogConfirm> createState() => _LogConfirmState();
}

class _LogConfirmState extends State<_LogConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LabMotion.standard,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final color = lab.forState(widget.signal);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // In over the first fifth, hold, then out. The exit is longer than the
          // entry so the message is legible rather than snatched away.
          final fade = t < .18
              ? t / .18
              : t > .72
              ? (1 - t) / .28
              : 1.0;
          final rise = (1 - Curves.easeOutCubic.transform(t.clamp(0, .4) / .4)) * 12;

          return Stack(
            children: [
              // The scan: a single accent line sweeping the whole screen, the
              // way a reader passes over a barcode.
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScanPainter(
                    progress: t,
                    color: color,
                    hair: lab.hair,
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: fade.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, rise),
                    child: _Plate(
                      name: widget.name,
                      detail: widget.detail,
                      color: color,
                      rising: widget.rising,
                      lab: lab,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({
    required this.name,
    required this.detail,
    required this.color,
    required this.rising,
    required this.lab,
  });

  final String name;
  final String detail;
  final Color color;
  final bool rising;
  final LabPalette lab;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
      decoration: BoxDecoration(
        color: lab.surface.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .18),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                rising ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                rising ? 'RESTOCKED' : 'LOGGED',
                style: context.label.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.itemName.copyWith(fontSize: 15),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: context.formula.copyWith(fontSize: 12.5, color: lab.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// One line sweeping down the screen, and a faint trail behind it.
class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required this.progress,
    required this.color,
    required this.hair,
  });

  final double progress;
  final Color color;
  final Color hair;

  @override
  void paint(Canvas canvas, Size size) {
    // The sweep runs slightly ahead of the plate so the line arrives first.
    final eased = Curves.easeInOutCubic.transform(progress.clamp(0, 1));
    final y = size.height * (.12 + .76 * eased);

    final trail = Rect.fromLTWH(0, y - 26, size.width, 26);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: .10)],
        ).createShader(trail),
    );

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: .55)
        ..strokeWidth = 1.2,
    );

    // A short brighter segment in the middle, so the eye has somewhere to land.
    final mid = size.width * .5;
    final halfSpan = size.width * .18 * math.sin(math.pi * progress.clamp(0, 1));
    canvas.drawLine(
      Offset(mid - halfSpan, y),
      Offset(mid + halfSpan, y),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, 1),
      Paint()..color = hair.withValues(alpha: .12),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) =>
      old.progress != progress || old.color != color || old.hair != hair;
}
