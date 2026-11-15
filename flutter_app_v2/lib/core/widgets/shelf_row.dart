import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/inventory/domain/item_view.dart';
import '../../features/inventory/domain/models.dart';
import '../motion.dart';
import '../theme/app_theme.dart';
import 'glass_jar.dart';
import 'jar_metrics.dart';
import 'vessel_tilt.dart';

/// Which way a row was swiped.
enum RowSwipe { use, restock }

/// One item on the shelf: vessel, name and level, then the quantity and its
/// flag.
///
/// A swipe is a *shortcut to the panel*, never a commit. Right offers use (or
/// damage, for apparatus), left offers restock, and either one opens the sheet
/// with the amount, date and note already filled in. Crossing 40% fires a
/// haptic tick so the gesture is felt before release.
///
/// An earlier version logged straight away when the drag passed 88%, on the
/// theory that it saved a tap. In the hand, a confident swipe always passes
/// 88%, so every swipe silently logged a number the user never chose. Nothing
/// is written until a button in the sheet is pressed.
class ShelfRow extends StatefulWidget {
  const ShelfRow({
    required this.item,
    required this.onTap,
    required this.onSwipe,
    this.onLongPress,
    this.compact = false,
    super.key,
  });

  final ItemView item;
  final VoidCallback onTap;

  /// Drops the subtitle and the tick row, so a long shelf fits more per screen.
  final bool compact;

  /// Right means use, left means restock. The caller opens the matching panel.
  final ValueChanged<RowSwipe> onSwipe;
  final VoidCallback? onLongPress;

  @override
  State<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<ShelfRow> {
  double _progress = 0;
  bool _ticked = false;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final item = widget.item;
    final metrics = item.metrics;
    final color = lab.forState(metrics.signal);
    final needsAttention = metrics.signal != StockSignal.fine;
    final caption = needsAttention
        ? stockCaption(metrics, piecewiseUnit: item.piecewise)
        : '';
    final compact = widget.compact;

    return Semantics(
      hint:
          'Tap to open. Hold for more actions. Swipe opens a confirmation '
          'panel.',
      child: Dismissible(
        key: ValueKey('row-${item.id}'),
        direction: DismissDirection.horizontal,
        dismissThresholds: const {
          DismissDirection.startToEnd: .42,
          DismissDirection.endToStart: .42,
        },
        onUpdate: (details) {
          if (!mounted) return;
          setState(() => _progress = details.progress);
          if (!_ticked && details.progress >= .42) {
            _ticked = true;
            HapticFeedback.selectionClick();
          } else if (_ticked && details.progress < .3) {
            _ticked = false;
          }
        },
        confirmDismiss: (direction) async {
          HapticFeedback.mediumImpact();
          widget.onSwipe(
            direction == DismissDirection.startToEnd
                ? RowSwipe.use
                : RowSwipe.restock,
          );
          if (mounted) setState(() => _progress = 0);
          // The swipe only opens a panel, so the row always snaps back rather
          // than leaving a hole underneath it.
          return false;
        },
        background: _SwipeHint(
          alignment: Alignment.centerLeft,
          label: item.useLabel,
          color: lab.sage,
          progress: _progress,
        ),
        secondaryBackground: _SwipeHint(
          alignment: Alignment.centerRight,
          label: 'restock',
          color: lab.accent,
          progress: _progress,
        ),
        child: Material(
          color: needsAttention ? lab.surface : lab.surface,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: needsAttention ? lab.wash(color) : null,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: needsAttention
                      ? lab.wash(color, .42)
                      : lab.hair,
                  width: 1,
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                11,
                compact ? 8 : 11,
                12,
                compact ? 8 : 11,
              ),
              child: Row(
                children: [
                  // A well the vessel stands in, so the glass reads against a
                  // slightly darker surface instead of the row itself.
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: lab.canvas.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: lab.hair),
                    ),
                    child: LeaningVessel(
                      metrics: metrics,
                      width: compact ? 22 : 30,
                      height: compact ? 30 : 40,
                      sensitivity: 1.5,
                      onTap: widget.onTap,
                      semanticLabel:
                          '${item.name}, ${formatQuantity(item.quantity)} '
                          '${item.unit}'
                          '${caption.isEmpty ? '' : ', $caption'}',
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.itemName,
                        ),
                        if (item.subtitle.isNotEmpty && !compact)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.formula,
                            ),
                          ),
                        if (!compact) ...[
                          const SizedBox(height: 8),
                          JarTicks(count: metrics.ticks, color: color),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CountUp(
                        value: item.quantity,
                        builder: (context, value) => Text(
                          formatQuantity(value),
                          style: context.figure,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.unit.toUpperCase(),
                          style: context.label.copyWith(
                            fontSize: LabType.micro,
                            color: lab.inkFaint,
                          ),
                        ),
                      ),
                      if (caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: lab.wash(color, .16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              caption.toUpperCase(),
                              style: context.label.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 9.5,
                                letterSpacing: .8,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({
    required this.alignment,
    required this.label,
    required this.color,
    required this.progress,
  });

  final Alignment alignment;
  final String label;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final armed = progress >= .42;
    final opacity = (progress * 2.2).clamp(0.0, 1.0);
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: armed ? .16 : .08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: armed ? .4 : .15)),
      ),
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == Alignment.centerLeft)
              Icon(Icons.remove_circle_outline, size: 18, color: color),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label.toUpperCase(),
                style: context.label.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            if (alignment != Alignment.centerLeft)
              Icon(Icons.add_circle_outline, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
