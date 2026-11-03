import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/inventory/domain/models.dart';
import '../motion.dart';
import '../theme/app_theme.dart';
import 'glass_jar.dart';
import 'jar_metrics.dart';

/// Which way a row was swiped.
enum RowSwipe { use, restock }

/// One reagent on the shelf, in direction C's layout: jar, name and level, then
/// the quantity and its flag on the right.
///
/// Swiping right logs use, swiping left restocks. Crossing roughly 40% of the
/// row's width fires a selection tick so the gesture is felt before release;
/// dragging most of the way commits immediately, otherwise the sheet opens with
/// the last amount pre-filled.
class ShelfRow extends StatefulWidget {
  const ShelfRow({
    required this.chemical,
    required this.index,
    required this.onTap,
    required this.onUse,
    required this.onRestock,
    required this.onFullSwipe,
    this.onLongPress,
    super.key,
  });

  final Chemical chemical;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onUse;
  final VoidCallback onRestock;
  final ValueChanged<RowSwipe> onFullSwipe;

  /// Opens the action wheel. Long-press is the discoverable alternative to
  /// swiping, and the only way to reach "set order level" from the shelf.
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
    final chemical = widget.chemical;
    final metrics = jarMetrics(
      quantity: chemical.quantity,
      initialQuantity: chemical.initialQuantity,
      threshold: chemical.lowStockThreshold,
    );
    final color = lab.forState(metrics.signal);
    final caption = stockCaption(metrics, piecewiseUnit: false);

    return Dismissible(
      key: ValueKey('shelf-${chemical.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: .42,
        DismissDirection.endToStart: .42,
      },
      onUpdate: (details) {
        if (!mounted) return;
        setState(() => _progress = details.progress);
        // Feel the threshold before letting go.
        if (!_ticked && details.progress >= .42) {
          _ticked = true;
          HapticFeedback.selectionClick();
        } else if (_ticked && details.progress < .3) {
          _ticked = false;
        }
      },
      confirmDismiss: (direction) async {
        final swipe = direction == DismissDirection.startToEnd
            ? RowSwipe.use
            : RowSwipe.restock;
        HapticFeedback.mediumImpact();
        if (_progress >= .88) {
          widget.onFullSwipe(swipe);
        } else if (swipe == RowSwipe.use) {
          widget.onUse();
        } else {
          widget.onRestock();
        }
        if (mounted) setState(() => _progress = 0);
        // The action opens a sheet; the row itself always snaps back so the
        // shelf doesn't jump around underneath it.
        return false;
      },
      background: _SwipeHint(
        alignment: Alignment.centerLeft,
        label: 'use',
        color: lab.sage,
        progress: _progress,
      ),
      secondaryBackground: _SwipeHint(
        alignment: Alignment.centerRight,
        label: 'restock',
        color: lab.ink,
        progress: _progress,
      ),
      child: Material(
        color: lab.card,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: lab.hair, width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(12, 11, 13, 11),
            child: Row(
              children: [
                GlassJar(
                  metrics: metrics,
                  onTap: widget.onTap,
                  semanticLabel:
                      '${chemical.name}, '
                      '${formatQuantity(chemical.quantity)} ${chemical.unit}'
                      '${caption.isEmpty ? '' : ', $caption'}',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chemical.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.itemName,
                      ),
                      if (chemical.formula.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(chemical.formula, style: context.formula),
                        ),
                      const SizedBox(height: 7),
                      JarTicks(count: metrics.ticks, color: color),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CountUp(
                      value: chemical.quantity,
                      builder: (context, value) => Text(
                        formatQuantity(value),
                        style: context.figure,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        chemical.unit.toUpperCase(),
                        style: context.label.copyWith(fontSize: 9),
                      ),
                    ),
                    if (caption.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          caption,
                          style: context.label.copyWith(
                            color: metrics.signal == StockSignal.fine
                                ? lab.soft.withValues(alpha: .7)
                                : color,
                            fontWeight: FontWeight.w700,
                            fontSize: 9,
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
    );
  }
}

/// The colour that appears underneath a row as it's dragged.
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
    // Fade in with the drag and firm up past the threshold, so the row tells
    // you when releasing will actually do something.
    final armed = progress >= .42;
    final opacity = (progress * 2.2).clamp(0.0, 1.0);
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: armed ? .16 : .09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == Alignment.centerLeft)
              Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: color,
              ),
            Text(
              label,
              style: context.aside.copyWith(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
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
