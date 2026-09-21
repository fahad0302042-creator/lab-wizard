import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/label_spec.dart';

/// Aspect ratio of a rendered label (width : height), the same 80 × 50 mm
/// shape as the single-label PDF.
const labelAspectRatio = 1.6;

/// Draws a clean black-on-white label: QR code on the left, name and
/// details on the right. Used for the on-screen preview and for the PNG
/// that *share image* produces (QR-03).
class LabelPainter extends CustomPainter {
  LabelPainter(this.label)
    : _qr = QrPainter(
        data: label.data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        gapless: true,
      );

  final LabelSpec label;
  final QrPainter _qr;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final pad = size.height * .08;
    final qrSide = size.height - pad * 2;
    canvas.save();
    canvas.translate(pad, pad);
    _qr.paint(canvas, Size.square(qrSide));
    canvas.restore();

    final textLeft = pad + qrSide + pad;
    final textWidth = size.width - textLeft - pad;
    if (textWidth <= 0) return;
    var y = pad;
    final titleSize = size.height * .13;
    final bodySize = size.height * .085;
    y += _paintText(
      canvas,
      label.title,
      Offset(textLeft, y),
      textWidth,
      TextStyle(
        color: Colors.black,
        fontSize: titleSize,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      maxLines: 3,
    );
    if (label.subtitle.isNotEmpty) {
      y += size.height * .03;
      y += _paintText(
        canvas,
        label.subtitle,
        Offset(textLeft, y),
        textWidth,
        TextStyle(color: const Color(0xFF333333), fontSize: bodySize),
        maxLines: 2,
      );
    }
    if (label.detail.isNotEmpty) {
      y += size.height * .03;
      _paintText(
        canvas,
        label.detail,
        Offset(textLeft, y),
        textWidth,
        TextStyle(color: const Color(0xFF555555), fontSize: bodySize * .9),
        maxLines: 1,
      );
    }
    final brand = TextPainter(
      text: TextSpan(
        text: 'Lab Wizard',
        style: TextStyle(color: const Color(0xFF888888), fontSize: bodySize * .7),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    brand.paint(
      canvas,
      Offset(size.width - pad - brand.width, size.height - pad - brand.height),
    );
  }

  double _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    double width,
    TextStyle style, {
    required int maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
    return painter.height;
  }

  @override
  bool shouldRepaint(covariant LabelPainter oldDelegate) =>
      oldDelegate.label.data != label.data ||
      oldDelegate.label.title != label.title ||
      oldDelegate.label.subtitle != label.subtitle ||
      oldDelegate.label.detail != label.detail;
}

/// Renders [label] as a PNG, [width] pixels wide (height follows
/// [labelAspectRatio]).
Future<Uint8List> renderLabelPng(LabelSpec label, {int width = 1200}) async {
  final height = (width / labelAspectRatio).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  LabelPainter(label).paint(canvas, Size(width.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not encode the label image.');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// On-screen preview of the label exactly as it will be shared.
class LabelPreview extends StatelessWidget {
  const LabelPreview(this.label, {super.key, this.width = 300});

  final LabelSpec label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR label for ${label.title}',
      image: true,
      child: SizedBox(
        width: width,
        height: width / labelAspectRatio,
        child: CustomPaint(painter: LabelPainter(label)),
      ),
    );
  }
}
