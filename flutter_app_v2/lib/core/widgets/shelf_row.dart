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
              color: needsAttention ? lab.wash(color) : null,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: needsAttention ? lab.wash(color, .45) : lab.hair,
                width: 1,
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              12,
              compact ? 8 : 11,
              13,
              compact ? 8 : 11,
            ),
            child: Row(
              children: [
                GlassJar(
                  metrics: metrics,
                  width: compact ? 22 : 30,
                  height: compact ? 30 : 40,
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
                        const SizedBox(height: 7),
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
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        item.unit.toUpperCase(),
                        style: context.label.copyWith(fontSize: LabType.micro),
                      ),
                    ),
                    if (caption.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          caption,
                          style: context.label.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: LabType.micro,
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
