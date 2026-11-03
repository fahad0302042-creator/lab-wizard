import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/inventory/domain/item_view.dart';
import '../../features/inventory/domain/models.dart';
import '../motion.dart';
import '../theme/app_theme.dart';
import 'glass_jar.dart';
import 'jar_metrics.dart';

/// Which way a row was swiped.
enum RowSwipe { use, restock }

/// One item on the shelf: jar, name and level, then the quantity and its flag.
///
/// Swiping right logs use (or damage, for apparatus), swiping left restocks.
/// Crossing 40% fires a haptic tick so the gesture is felt before release;
/// dragging most of the way commits immediately, otherwise the sheet opens with
/// the amount this item is usually logged at.
class ShelfRow extends StatefulWidget {
  const ShelfRow({
    required this.item,
    required this.onTap,
    required this.onUse,
    required this.onRestock,
    required this.onFullSwipe,
    this.onLongPress,
    super.key,
  });

  final ItemView item;
  final VoidCallback onTap;
  final VoidCallback onUse;
  final VoidCallback onRestock;
  final ValueChanged<RowSwipe> onFullSwipe;
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
    final caption = stockCaption(metrics, piecewiseUnit: item.piecewise);

    return Dismissible(
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
        // The action opens a sheet, so the row always snaps back rather than
        // leaving a hole underneath it.
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
                      '${item.name}, ${formatQuantity(item.quantity)} '
                      '${item.unit}'
                      '${caption.isEmpty ? '' : ', $caption'}',
                ),
                const SizedBox(width: 12),
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
                      if (item.subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(item.subtitle, style: context.formula),
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
                      value: item.quantity,
                      builder: (context, value) => Text(
                        formatQuantity(value),
                        style: context.figure,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        item.unit.toUpperCase(),
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
        color: color.withValues(alpha: armed ? .16 : .09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == Alignment.centerLeft)
              Icon(Icons.remove_circle_outline, size: 18, color: color),
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
