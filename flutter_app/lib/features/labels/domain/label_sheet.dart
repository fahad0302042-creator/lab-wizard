import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'label_spec.dart';

/// Grid options for an A4 sheet of labels (QR-01/QR-02). The 40-per-page
/// grid is the one the web app prints; the larger grids suit equipment.
enum LabelSheetLayout {
  small(columns: 5, rows: 8, name: '40 per page', hint: 'about 38 × 35 mm'),
  medium(columns: 4, rows: 6, name: '24 per page', hint: 'about 48 × 46 mm'),
  large(columns: 3, rows: 4, name: '12 per page', hint: 'about 63 × 69 mm');

  const LabelSheetLayout({
    required this.columns,
    required this.rows,
    required this.name,
    required this.hint,
  });

  final int columns;
  final int rows;
  final String name;
  final String hint;

  int get perPage => columns * rows;

  double get _qrMm => switch (this) {
    LabelSheetLayout.small => 17,
    LabelSheetLayout.medium => 24,
    LabelSheetLayout.large => 34,
  };

  double get _titleSize => switch (this) {
    LabelSheetLayout.small => 7,
    LabelSheetLayout.medium => 9,
    LabelSheetLayout.large => 11,
  };

  double get _bodySize => switch (this) {
    LabelSheetLayout.small => 6,
    LabelSheetLayout.medium => 7,
    LabelSheetLayout.large => 8.5,
  };
}

/// Number of A4 pages [count] labels take in [layout].
int labelPageCount(int count, LabelSheetLayout layout) =>
    count <= 0 ? 0 : (count + layout.perPage - 1) ~/ layout.perPage;

/// A4 sheet(s) with one cell per label, filled row by row.
pw.Document buildLabelSheet(
  List<LabelSpec> labels, {
  LabelSheetLayout layout = LabelSheetLayout.small,
  String title = 'Lab Wizard QR labels',
}) {
  final document = pw.Document(title: title, author: 'Lab Wizard');
  for (var offset = 0; offset < labels.length; offset += layout.perPage) {
    final pageItems = labels.skip(offset).take(layout.perPage).toList();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          children: List.generate(layout.rows, (row) {
            return pw.Expanded(
              child: pw.Row(
                children: List.generate(layout.columns, (column) {
                  final index = row * layout.columns + column;
                  return pw.Expanded(
                    child: index >= pageItems.length
                        ? pw.SizedBox()
                        : _labelCell(pageItems[index], layout),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
  return document;
}

/// One label on its own small page (80 × 50 mm) for label printers or a
/// clean PDF to share (QR-03).
pw.Document buildSingleLabel(LabelSpec label) {
  final document = pw.Document(
    title: '${label.title} label',
    author: 'Lab Wizard',
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(
        80 * PdfPageFormat.mm,
        50 * PdfPageFormat.mm,
        marginAll: 4 * PdfPageFormat.mm,
      ),
      build: (_) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: label.data,
            width: 38 * PdfPageFormat.mm,
            height: 38 * PdfPageFormat.mm,
          ),
          pw.SizedBox(width: 4 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label.title,
                  maxLines: 3,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (label.subtitle.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    label.subtitle,
                    maxLines: 2,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
                if (label.detail.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    label.detail,
                    maxLines: 1,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
                pw.Spacer(),
                pw.Text(
                  'Lab Wizard',
                  style: const pw.TextStyle(
                    fontSize: 6,
                    color: PdfColors.grey500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return document;
}

pw.Widget _labelCell(LabelSpec label, LabelSheetLayout layout) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: .45),
    ),
    padding: const pw.EdgeInsets.all(4),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: label.data,
          width: layout._qrMm * PdfPageFormat.mm,
          height: layout._qrMm * PdfPageFormat.mm,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          label.title,
          maxLines: 2,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: layout._titleSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (label.subtitle.isNotEmpty)
          pw.Text(
            label.subtitle,
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: layout._bodySize,
              color: PdfColors.grey700,
            ),
          ),
        if (label.detail.isNotEmpty)
          pw.Text(
            label.detail,
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: layout._bodySize,
              color: PdfColors.grey600,
            ),
          ),
      ],
    ),
  );
}
