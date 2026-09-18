import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/inventory/domain/models.dart';
import '../theme/app_theme.dart';

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
      decoration: BoxDecoration(color: context.paperColor),
      child: CustomPaint(
        painter: _PaperPainter(
          ruled: context.ruledColor,
          margin: LabColors.marginRed.withValues(alpha: .28),
        ),
        child: child,
      ),
    );
    return includeSafeArea ? SafeArea(child: content) : content;
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({required this.ruled, required this.margin});

  final Color ruled;
  final Color margin;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = ruled
      ..strokeWidth = 1;
    for (double y = 94; y < size.height; y += 34) {
      canvas.drawLine(
        Offset.zero.translate(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }
    final marginPaint = Paint()
      ..color = margin
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(28, 0), Offset(28, size.height), marginPaint);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.ruled != ruled || oldDelegate.margin != margin;
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SketchTitle(text)),
        ?trailing,
      ],
    );
  }
}

class SketchTitle extends StatefulWidget {
  const SketchTitle(this.text, {this.fontSize = 34, super.key});

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
      duration: const Duration(milliseconds: 540),
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
    return RepaintBoundary(
      child: CustomPaint(
        painter: _UnderlinePainter(
          progress: reduceMotion
              ? const AlwaysStoppedAnimation(1)
              : _controller,
          color: context.inkColor,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text(
            widget.text,
            style: TextStyle(
              fontFamily: 'Kalam',
              fontSize: widget.fontSize,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
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
    final width = math.min(size.width * .62, 180.0) * progress.value;
    if (width <= 0) return;
    final path = Path()
      ..moveTo(1, size.height - 3)
      ..cubicTo(
        width * .2,
        size.height - 9,
        width * .36,
        size.height + 1,
        width * .55,
        size.height - 4,
      )
      ..cubicTo(
        width * .73,
        size.height - 8,
        width * .83,
        size.height + 1,
        width,
        size.height - 5,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
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
    this.accent,
    this.rotation = 0,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? accent;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: context.isDark ? const Color(0xFF24221E) : const Color(0xFFFFFEFA),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: (accent ?? context.inkColor).withValues(alpha: .18),
          width: 1.2,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(19),
          bottomRight: Radius.circular(13),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (rotation == 0) return card;
    return Transform.rotate(angle: rotation, child: card);
  }
}

class StaggerIn extends StatelessWidget {
  const StaggerIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 260 + math.min(index, 8) * 42),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
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
    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      tween: Tween(end: value),
      builder: (_, animated, _) =>
          Text('${formatQuantity(animated)}$suffix', style: style),
    );
  }
}

class StockBar extends StatelessWidget {
  const StockBar({required this.progress, required this.status, super.key});

  final double progress;
  final StockState status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      tween: Tween(end: progress),
      builder: (_, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          minHeight: 8,
          value: value,
          backgroundColor: color.withValues(alpha: .12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

Color statusColor(StockState status) => switch (status) {
  StockState.healthy => LabColors.green,
  StockState.low => LabColors.amber,
  StockState.empty => LabColors.marginRed,
};

String statusLabel(StockState status) => switch (status) {
  StockState.healthy => 'in stock',
  StockState.low => 'low stock',
  StockState.empty => 'out of stock',
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final StockState status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == StockState.empty ? Icons.error_outline : Icons.circle,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 22),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .75, end: 1),
            curve: Curves.elasticOut,
            duration: const Duration(milliseconds: 800),
            builder: (_, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Icon(icon, size: 54, color: context.mutedInkColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Kalam',
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
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
