import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/inventory/domain/models.dart';
import '../theme/app_theme.dart';

enum NotebookTape { none, yellow, blue, green, pink }

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
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: context.paperColor,
        boxShadow: const [
          BoxShadow(
            color: Color(0x35000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _PaperPainter(
          ruled: context.ruledColor,
          margin: context.marginLineColor,
          desk: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: child,
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
  });

  final Color ruled;
  final Color margin;
  final Color desk;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = ruled
      ..strokeWidth = 1;
    for (double y = 70; y < size.height; y += 27) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    canvas.drawLine(
      const Offset(38.5, 0),
      Offset(38.5, size.height),
      Paint()
        ..color = margin
        ..strokeWidth = 1.4,
    );

    // A restrained torn-paper edge, matching the web page without making the
    // Android status area noisy.
    final tear = Path()..moveTo(0, 1);
    for (double x = 0; x <= size.width + 12; x += 12) {
      tear
        ..lineTo(x + 6, 4)
        ..lineTo(x + 12, 1);
    }
    canvas.drawPath(
      tear,
      Paint()
        ..color = desk.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.ruled != ruled ||
      oldDelegate.margin != margin ||
      oldDelegate.desk != desk;
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
        Expanded(child: SketchTitle(text, fontSize: fontSize ?? 35)),
        ?trailing,
      ],
    );
  }
}

class SketchTitle extends StatefulWidget {
  const SketchTitle(this.text, {this.fontSize = 35, super.key});

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

    final card = Stack(
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

class StaggerIn extends StatelessWidget {
  const StaggerIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 240 + math.min(index, 7) * 38),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class AnimatedQuantity extends StatelessWidget {
  const AnimatedQuantity(this.value, {this.suffix = '', this.style, super.key});

  final double value;
  final String suffix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // Screen readers get the final value straight away instead of the
    // intermediate numbers of the count-up animation.
    return Semantics(
      label: '${formatQuantity(value)}$suffix',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        tween: Tween(end: value),
        builder: (_, animated, _) =>
            Text('${formatQuantity(animated)}$suffix', style: style),
      ),
    );
  }
}

class StockBar extends StatelessWidget {
  const StockBar({required this.progress, required this.status, super.key});

  final double progress;
  final StockState status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StockState.healthy => context.healthyColor,
      StockState.low => context.lowColor,
      StockState.empty => context.marginRedColor,
    };
    return Semantics(
      label:
          '${stockSpoken(status)}, '
          '${(progress.clamp(0, 1) * 100).round()} percent of the '
          'starting amount',
      child: TweenAnimationBuilder<double>(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        tween: Tween(end: progress.clamp(0, 1)),
        builder: (_, value, _) => SizedBox(
          height: 17,
          width: double.infinity,
          child: CustomPaint(
            painter: _HatchedBarPainter(
              progress: value,
              color: color,
              ink: context.inkColor,
              status: status,
            ),
          ),
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
              fontFamily: 'Caveat',
              fontSize: 17,
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
    this.fontSize = 22,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? context.marginRedColor : context.mutedInkColor,
              fontFamily: 'Caveat',
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            duration: const Duration(milliseconds: 700),
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
