import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/inventory/domain/models.dart';
import '../motion/lab_motion.dart';
import '../theme/app_theme.dart';

export '../motion/lab_motion.dart'
    show ScanBurst, flyActionChip, labSpring, showLabSheet;

enum NotebookTape { none, yellow, blue, green, pink }

/// Page inset. Wide enough for a thumb, narrow enough that names still fit.
const double notebookGutter = 20;

class NotebookPage extends StatelessWidget {
  const NotebookPage({
    required this.child,
    this.includeSafeArea = true,
    super.key,
  });

  final Widget child;
  final bool includeSafeArea;

  @override
  Widget build(BuildContext context) {
    // A Material, not a coloured box, so list tiles and ink splashes paint
    // on the page (Flutter asserts when a box sits between a tile and its
    // Material).
    final content = SheetStage(
      child: Material(color: context.paperColor, child: child),
    );
    return includeSafeArea ? SafeArea(child: content) : content;
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.text, {this.trailing, this.fontSize, super.key});

  final String text;
  final Widget? trailing;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SketchTitle(text, fontSize: fontSize ?? 22)),
        // Flexible so a wide trailing button wraps its label under large
        // text instead of pushing past the edge.
        if (trailing != null) Flexible(child: trailing!),
      ],
    );
  }
}

class SketchTitle extends StatelessWidget {
  const SketchTitle(this.text, {this.fontSize = 22, super.key});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // A heading for screen readers so TalkBack's heading navigation works.
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.inkColor,
          ),
        ),
      ),
    );
  }
}

class NotebookCard extends StatelessWidget {
  const NotebookCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.accent,
    this.rotation = 0,
    this.tape = NotebookTape.none,
    this.paperclip = false,
    this.alternate = false,
    this.color,
    this.bordered = true,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? accent;

  /// Kept so existing call sites compile. The clinical surface does not
  /// tilt, tape, or clip a card.
  final double rotation;
  final NotebookTape tape;
  final bool paperclip;
  final bool alternate;
  final Color? color;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(12));
    return _CardPress(
      enabled: onTap != null || onLongPress != null,
      child: Material(
        color: color ?? context.cardColor,
        shape: RoundedRectangleBorder(
          side: bordered
              ? BorderSide(color: context.ruledColor)
              : BorderSide.none,
          borderRadius: radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: DecoratedBox(
            decoration: accent == null
                ? const BoxDecoration()
                : BoxDecoration(
                    border: Border(left: BorderSide(color: accent!, width: 3)),
                  ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Presses the card in, then springs back. Still cards (no tap) are left
/// alone so a sitting screen does not keep a ticker.
class _CardPress extends StatefulWidget {
  const _CardPress({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_CardPress> createState() => _CardPressState();
}

class _CardPressState extends State<_CardPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      lowerBound: 0.9,
      upperBound: 1.08,
      value: 1,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent _) {
    // A fling can deliver the pointer after the card has scrolled away.
    if (!mounted || !widget.enabled) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _press.animateTo(
      0.965,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _up(PointerEvent _) {
    if (!mounted || !widget.enabled) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.value = 1;
      return;
    }
    _press.animateTo(1, curve: labSpring);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) =>
            Transform.scale(scale: _press.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class StaggerIn extends StatefulWidget {
  const StaggerIn({
    required this.index,
    required this.child,
    this.onceKey,
    super.key,
  });

  final int index;
  final Widget child;

  /// When set, the rise plays once per app launch. Scrolling a row off and
  /// back does not play it again.
  final Object? onceKey;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn> {
  static final Set<Object> _played = <Object>{};
  late final bool _skip;

  @override
  void initState() {
    super.initState();
    final key = widget.onceKey;
    _skip = key != null && _played.contains(key);
    if (key != null) _played.add(key);
  }

  @override
  Widget build(BuildContext context) {
    if (_skip || MediaQuery.disableAnimationsOf(context)) return widget.child;
    final index = math.min(widget.index, 8);
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 220 + index * 40),
      curve: labSpring,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        final travel = value.clamp(0.0, 1.2);
        return Opacity(
          opacity: travel.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - travel)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class AnimatedQuantity extends StatefulWidget {
  const AnimatedQuantity(this.value, {this.suffix = '', this.style, super.key});

  final double value;
  final String suffix;
  final TextStyle? style;

  @override
  State<AnimatedQuantity> createState() => _AnimatedQuantityState();
}

class _AnimatedQuantityState extends State<AnimatedQuantity>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _to = widget.value;
    _roll = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void didUpdateWidget(AnimatedQuantity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _to) return;
    _from = _sample(_roll.value);
    _to = widget.value;
    if (MediaQuery.disableAnimationsOf(context)) {
      _roll.value = 1;
      return;
    }
    _roll.forward(from: 0);
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  double _sample(double t) {
    final curved = labSpring.transform(t.clamp(0.0, 1.0));
    return _from + (_to - _from) * curved;
  }

  String _label() {
    if (_roll.value >= 1) return '${formatQuantity(_to)}${widget.suffix}';
    var animated = _sample(_roll.value);
    if (_to >= 0 && _from >= 0 && animated < 0) animated = 0;
    final whole = _to == _to.roundToDouble();
    if (!whole) return '${formatQuantity(animated)}${widget.suffix}';
    final past = animated - _to;
    final overshooting = _to >= _from ? past > 0.001 : past < -0.001;
    if (overshooting && past.abs() < 1) {
      final shown = _to.round() + (past > 0 ? 1 : -1);
      if (shown < 0 && _to >= 0) return '0${widget.suffix}';
      return '$shown${widget.suffix}';
    }
    return '${animated.round()}${widget.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    // Screen readers get the final value straight away instead of the
    // intermediate numbers of the count-up animation.
    return Semantics(
      label: '${formatQuantity(widget.value)}${widget.suffix}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _roll,
        builder: (context, _) {
          final pulse = _roll.value >= 1
              ? 1.0
              : 1 + 0.05 * math.sin(_roll.value * math.pi);
          return Transform.scale(
            scale: pulse,
            child: Text(_label(), style: widget.style),
          );
        },
      ),
    );
  }
}

class StockBar extends StatefulWidget {
  const StockBar({
    required this.progress,
    required this.status,
    this.height = 9,
    super.key,
  });

  final double progress;
  final StockState status;
  final double height;

  @override
  State<StockBar> createState() => _StockBarState();
}

class _StockBarState extends State<StockBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tint;
  Color? _from;

  @override
  void initState() {
    super.initState();
    _tint = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(StockBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) return;
    _from = _statusColor(context, oldWidget.status);
    if (MediaQuery.disableAnimationsOf(context)) {
      _tint.value = 1;
      return;
    }
    _tint.forward(from: 0);
  }

  @override
  void dispose() {
    _tint.dispose();
    super.dispose();
  }

  Color _statusColor(BuildContext context, StockState status) =>
      switch (status) {
        StockState.healthy => context.healthyColor,
        StockState.low => context.lowColor,
        StockState.empty => context.marginRedColor,
      };

  @override
  Widget build(BuildContext context) {
    final target = widget.progress.clamp(0.0, 1.0);
    final live = _statusColor(context, widget.status);
    return Semantics(
      label:
          '${stockSpoken(widget.status)}, '
          '${(target * 100).round()} percent of the '
          'starting amount',
      child: TweenAnimationBuilder<double>(
        duration: context.motion(const Duration(milliseconds: 420)),
        curve: labSpring,
        tween: Tween(end: target),
        builder: (_, value, _) => AnimatedBuilder(
          animation: _tint,
          builder: (context, _) {
            final color = _from == null || _tint.value >= 1
                ? live
                : Color.lerp(_from, live, _tint.value) ?? live;
            return SizedBox(
              height: widget.height,
              width: double.infinity,
              child: CustomPaint(
                painter: _HatchedBarPainter(
                  progress: value.clamp(0.0, 1.08),
                  color: color,
                  ink: context.inkColor,
                  status: widget.status,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Rounded stock track. Status is also spoken and written beside the bar;
/// an empty track keeps a hairline so "empty" is not a missing widget.
class _HatchedBarPainter extends CustomPainter {
  const _HatchedBarPainter({
    required this.progress,
    required this.color,
    required this.ink,
    required this.status,
  });

  final double progress;
  final Color color;
  final Color ink;
  final StockState status;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(
      shape,
      Paint()..color = ink.withValues(alpha: .1),
    );
    final fillWidth = math.max(0.0, size.width * progress.clamp(0.0, 1.08));
    if (fillWidth > 0) {
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        Paint()..color = color,
      );
      canvas.restore();
    } else if (status == StockState.empty) {
      final y = size.height / 2;
      canvas.drawLine(
        Offset(4, y),
        Offset(size.width - 4, y),
        Paint()
          ..color = ink.withValues(alpha: .28)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchedBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.ink != ink ||
      oldDelegate.status != status;
}

Color statusColor(StockState status) => switch (status) {
  StockState.healthy => LabColors.green,
  StockState.low => LabColors.amber,
  StockState.empty => LabColors.marginRed,
};

String statusLabel(StockState status) => switch (status) {
  StockState.healthy => 'in stock',
  StockState.low => 'getting low',
  StockState.empty => 'out of stock',
};

String stockCaption(StockState status) => switch (status) {
  StockState.healthy => 'in stock ✓',
  StockState.low => 'getting low!',
  StockState.empty => 'out of stock!',
};

/// Plain words for screen readers (no symbols to read out).
String stockSpoken(StockState status) => switch (status) {
  StockState.healthy => 'in stock',
  StockState.low => 'low stock',
  StockState.empty => 'out of stock',
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final StockState status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StockState.healthy => context.healthyColor,
      StockState.low => context.lowColor,
      StockState.empty => context.marginRedColor,
    };
    return Semantics(
      label: stockSpoken(status),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            stockCaption(status),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class NotebookFilterWord extends StatelessWidget {
  const NotebookFilterWord({
    required this.label,
    required this.selected,
    required this.onTap,
    this.fontSize = 20,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? context.healthyColor
                      : context.mutedInkColor,
                  fontSize: fontSize,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header of a collapsible "more details" block: chevron, title and a short
/// summary. Title and summary share one paragraph so the summary simply
/// wraps under the title on narrow screens or with large text instead of
/// pushing the row past its edge.
class DetailsToggle extends StatelessWidget {
  const DetailsToggle({
    required this.expanded,
    required this.summary,
    required this.onTap,
    this.title = 'more details',
    super.key,
  });

  final bool expanded;
  final String summary;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: context.mutedInkColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.inkColor,
                      ),
                    ),
                    const TextSpan(text: '   '),
                    TextSpan(
                      text: summary,
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CircledNotebookButton extends StatelessWidget {
  const CircledNotebookButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? context.inkColor;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class MarginNote extends StatelessWidget {
  const MarginNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Lives in a narrow margin: shrinks rather than clips with large text.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 2,
        style: TextStyle(
          color: context.marginRedColor,
          fontSize: 13,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class EmptyNotebookState extends StatelessWidget {
  const EmptyNotebookState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .8, end: 1),
            curve: Curves.elasticOut,
            duration: context.motion(const Duration(milliseconds: 700)),
            builder: (_, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Icon(icon, size: 48, color: context.mutedInkColor),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.mutedInkColor),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
