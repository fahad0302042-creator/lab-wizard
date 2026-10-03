import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/inventory/domain/models.dart';
import '../motion/lab_motion.dart';
import '../theme/app_theme.dart';

export '../motion/lab_motion.dart'
    show ScanBurst, flyActionChip, labSpring, showLabSheet;

enum NotebookTape { none, yellow, blue, green, pink }

/// Content starts just past the red margin line. The gutter used to be 54px,
/// which ate the name column on a phone.
const double notebookGutter = 26;

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
    // The shadow stays on a DecoratedBox; the paper colour is a Material so
    // list tiles and ink splashes on a page paint on the paper (Flutter
    // asserts when a coloured box sits between a tile and its Material).
    final content = SheetStage(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x35000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: context.paperColor,
          child: CustomPaint(
            painter: _PaperPainter(
              ruled: context.ruledColor,
              margin: context.marginLineColor,
              desk: Theme.of(context).scaffoldBackgroundColor,
              ink: context.inkColor,
            ),
            child: child,
          ),
        ),
      ),
    );
    return includeSafeArea ? SafeArea(child: content) : content;
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({
    required this.ruled,
    required this.margin,
    required this.desk,
    required this.ink,
  });

  final Color ruled;
  final Color margin;
  final Color desk;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final linePaint = Paint()
      ..color = ruled
      ..strokeWidth = 1;
    for (double y = 36; y < size.height; y += 27) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    canvas.drawLine(
      const Offset(10, 16),
      Offset(10, size.height),
      Paint()
        ..color = margin
        ..strokeWidth = 1.6,
    );

    // Desk colour shows through a jagged tear, with an ink edge and shadow.
    const depth = 13.0;
    final tear = Path()..moveTo(0, 0);
    var x = 0.0;
    var dip = true;
    while (x < size.width) {
      final next = math.min(x + 12, size.width);
      tear.lineTo(next, dip ? depth : 3);
      x = next;
      dip = !dip;
      if (next >= size.width) break;
    }
    tear
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawShadow(tear, ink.withValues(alpha: .5), 3.5, false);
    canvas.drawPath(tear, Paint()..color = desk);
    canvas.drawPath(
      tear,
      Paint()
        ..color = ink.withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.ruled != ruled ||
      oldDelegate.margin != margin ||
      oldDelegate.desk != desk ||
      oldDelegate.ink != ink;
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
        Expanded(child: SketchTitle(text, fontSize: fontSize ?? 26)),
        // Flexible so a wide trailing button wraps its label under large
        // text instead of pushing past the edge.
        if (trailing != null) Flexible(child: trailing!),
      ],
    );
  }
}

class SketchTitle extends StatefulWidget {
  const SketchTitle(this.text, {this.fontSize = 26, super.key});

  final String text;
  final double fontSize;

  @override
  State<SketchTitle> createState() => _SketchTitleState();
}

class _SketchTitleState extends State<SketchTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the underline is simply drawn, no ticker runs.
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // A heading for screen readers so TalkBack's heading navigation works.
    return Semantics(
      header: true,
      child: RepaintBoundary(
        child: Transform.rotate(
          angle: -.012,
          alignment: Alignment.centerLeft,
          child: CustomPaint(
            painter: _UnderlinePainter(
              progress: reduceMotion
                  ? const AlwaysStoppedAnimation(1)
                  : _controller,
              color: context.marginRedColor,
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                widget.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: widget.fontSize,
                  height: .98,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  _UnderlinePainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = math.min(size.width * .68, 150.0) * progress.value;
    if (width <= 0) return;
    final y = size.height - 3;
    final path = Path()
      ..moveTo(1, y)
      ..cubicTo(width * .18, y - 5, width * .34, y + 3, width * .51, y)
      ..cubicTo(width * .68, y - 4, width * .82, y + 3, width, y - 1);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter oldDelegate) =>
      oldDelegate.color != color;
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
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? accent;
  final double rotation;
  final NotebookTape tape;
  final bool paperclip;
  final bool alternate;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkColor;
    final borderColor = accent == null
        ? ink.withValues(alpha: .88)
        : Color.lerp(ink, accent, .34)!;
    final radius = alternate
        ? const BorderRadius.only(
            topLeft: Radius.elliptical(9, 3),
            topRight: Radius.elliptical(3, 9),
            bottomLeft: Radius.elliptical(3, 9),
            bottomRight: Radius.elliptical(9, 3),
          )
        : const BorderRadius.only(
            topLeft: Radius.elliptical(3, 9),
            topRight: Radius.elliptical(9, 3),
            bottomLeft: Radius.elliptical(8, 3),
            bottomRight: Radius.elliptical(3, 9),
          );

    final card = _CardPress(
      enabled: onTap != null || onLongPress != null,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 6,
                  offset: Offset(2, 3),
                ),
              ],
            ),
            child: Material(
              color: context.cardColor,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: borderColor, width: 1.45),
                borderRadius: radius,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
          if (tape != NotebookTape.none)
            Positioned(
              top: -10,
              left: alternate ? null : 28,
              right: alternate ? 32 : null,
              child: _WashiTape(color: _tapeColor(tape)),
            ),
          if (paperclip)
            const Positioned(
              top: -15,
              right: 22,
              child: SizedBox(
                width: 28,
                height: 46,
                child: CustomPaint(painter: _PaperclipPainter()),
              ),
            ),
        ],
      ),
    );
    return rotation == 0
        ? card
        : Transform.rotate(angle: rotation, child: card);
  }

  static Color _tapeColor(NotebookTape tape) => switch (tape) {
    NotebookTape.yellow => LabColors.tapeYellow,
    NotebookTape.blue => LabColors.tapeBlue,
    NotebookTape.green => LabColors.tapeGreen,
    NotebookTape.pink => LabColors.tapePink,
    NotebookTape.none => Colors.transparent,
  };
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
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) return;
    _press.animateTo(
      0.965,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _up(PointerEvent _) {
    if (!widget.enabled) return;
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

class _WashiTape extends StatelessWidget {
  const _WashiTape({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: .065,
      child: Container(
        width: 60,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperclipPainter extends CustomPainter {
  const _PaperclipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8, 8)
      ..cubicTo(8, 3, 20, 3, 20, 10)
      ..lineTo(20, 32)
      ..cubicTo(20, 38, 12, 38, 12, 32)
      ..lineTo(12, 14);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8A8578)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

/// Stock bar fill. The hatch pattern changes with the status as well as the
/// colour (A11Y-04): sparse diagonal stripes when healthy, dense stripes when
/// low, and a cross-hatch when empty, so the state is readable without
/// colour vision.
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
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndCorners(
      rect.deflate(1),
      topLeft: const Radius.elliptical(10, 4),
      topRight: const Radius.elliptical(4, 10),
      bottomLeft: const Radius.elliptical(4, 10),
      bottomRight: const Radius.elliptical(10, 4),
    );
    canvas.save();
    canvas.clipRRect(shape);
    final fillWidth = math.max(0.0, (size.width - 2) * progress);
    final fill = Rect.fromLTWH(1, 1, fillWidth, size.height - 2);
    canvas.drawRect(fill, Paint()..color = color);
    canvas.save();
    canvas.clipRect(fill);
    final stripe = Paint()
      ..color = Color.lerp(color, Colors.black, .18)!
      ..strokeWidth = status == StockState.healthy ? 3.2 : 2.4;
    final gap = status == StockState.healthy ? 12.0 : 6.0;
    for (double x = -size.height; x < fillWidth + size.height; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + 9, 0), stripe);
      if (status == StockState.empty) {
        canvas.drawLine(Offset(x, 0), Offset(x + 9, size.height), stripe);
      }
    }
    // An empty bar still shows a faint cross-hatch across the whole track
    // so "empty" is not just "nothing".
    if (progress <= 0) {
      canvas.restore();
      canvas.save();
      canvas.clipRRect(shape);
      final ghost = Paint()
        ..color = ink.withValues(alpha: .18)
        ..strokeWidth = 1.2;
      for (double x = -size.height; x < size.width + size.height; x += 7) {
        canvas.drawLine(Offset(x, size.height), Offset(x + 9, 0), ghost);
        canvas.drawLine(Offset(x, 0), Offset(x + 9, size.height), ghost);
      }
    }
    canvas.restore();
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status == StockState.empty
              ? LabColors.highlighter.withValues(alpha: .75)
              : color.withValues(alpha: .12),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(2),
            topRight: Radius.circular(9),
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            stockCaption(status),
            style: TextStyle(
              color: status == StockState.empty ? context.inkColor : color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
                  color: selected ? context.inkColor : context.mutedInkColor,
                  fontSize: fontSize,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  decoration: selected ? TextDecoration.underline : null,
                  decorationColor: context.marginRedColor,
                  decorationThickness: 2,
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
                        fontFamily: 'Caveat',
                        fontSize: 22,
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
        side: BorderSide(color: foreground, width: 1.8),
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
    return Transform.rotate(
      angle: -.12,
      // Lives in a narrow margin: shrinks rather than clips with large text.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 2,
          style: TextStyle(
            color: context.marginRedColor,
            fontFamily: 'Caveat',
            fontSize: 16,
            height: .9,
            fontWeight: FontWeight.w700,
          ),
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
            style: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 27,
              fontWeight: FontWeight.w700,
            ),
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
