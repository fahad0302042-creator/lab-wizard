import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../inventory/domain/models.dart';
import '../domain/monthly_report.dart';

/// Draws the monthly sheet that goes on the staff-room wall.
///
/// Two shelves, two sections, each starting on its own page. The added column
/// only appears when something was actually restocked that month — on a month
/// with no deliveries it was a column of zeroes that told the reader nothing.
class ReportPdf {
  const ReportPdf._();

  static Future<Uint8List> build({
    required List<MonthlyReport> reports,
    required DateTime generatedAt,
    Uint8List? logoBytes,
    String organizationName = '',
  }) async {
    // Two passes: the first measures how long the document is, the second
    // prints "Page 3 of 7" on it. A footer written during a single pass cannot
    // know the total, and guessing looks worse than measuring.
    final probe = _compose(
      reports: reports,
      generatedAt: generatedAt,
      totalPages: null,
      logoBytes: logoBytes,
      organizationName: organizationName.trim(),
    );
    final totalPages = probe.document.pdfPageList.pages.length;
    final document = _compose(
      reports: reports,
      generatedAt: generatedAt,
      totalPages: totalPages,
      logoBytes: logoBytes,
      organizationName: organizationName.trim(),
    );
    return document.save();
  }

  static pw.Document _compose({
    required List<MonthlyReport> reports,
    required DateTime generatedAt,
    required int? totalPages,
    required Uint8List? logoBytes,
    required String organizationName,
  }) {
    final document = pw.Document(
      title: 'Lab Wizard report',
      author: 'Lab Wizard',
      creator: 'Lab Wizard 2',
    );
    for (final report in reports) {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 26),
          header: (context) => _masthead(
            report, generatedAt, logoBytes, organizationName,
          ),
          footer: (context) => _footer(report, context, totalPages),
          build: (context) => [
            if (!report.isEmpty) _kpis(report),
            if (report.isEmpty)
              _nothingLogged(report)
            else
              _table(report),
            if (!report.isEmpty)
              pw.SizedBox(height: 14),
            if (!report.isEmpty)
              pw.Text(
                report.footnote,
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
          ],
        ),
      );
    }
    return document;
  }

  static pw.Widget _masthead(
    MonthlyReport report,
    DateTime generatedAt,
    Uint8List? logoBytes,
    String organizationName,
  ) {
    final generated = DateFormat(
      'd MMM yyyy, HH:mm',
    ).format(generatedAt.toLocal());
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 9),
      margin: const pw.EdgeInsets.only(bottom: 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 1.4),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logoBytes != null) ...[
            pw.Image(
              pw.MemoryImage(logoBytes),
              width: 42,
              height: 42,
              fit: pw.BoxFit.contain,
            ),
            pw.SizedBox(width: 9),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  organizationName.isEmpty
                      ? 'Inventory report'
                      : organizationName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                report.title,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Period: ${report.periodLabel}  ·  Generated: $generated',
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(
    MonthlyReport report,
    pw.Context context,
    int? totalPages,
  ) {
    final page = context.pageNumber;
    final of = totalPages == null ? '' : ' of $totalPages';
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            report.title,
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
          pw.Spacer(),
          pw.Text(
            'Page $page$of',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kpis(MonthlyReport report) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        children: [
          _kpi('${report.itemsConsumed}', 'items consumed'),
          pw.SizedBox(width: 10),
          _kpi('${report.events}', 'consumption events'),
          pw.SizedBox(width: 10),
          _kpi('${report.lowStockCount}', 'low stock items'),
        ],
      ),
    );
  }

  static pw.Widget _kpi(String value, String label) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label.toUpperCase(),
              style: const pw.TextStyle(
                fontSize: 7,
                letterSpacing: 0.5,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _nothingLogged(MonthlyReport report) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 26),
      child: pw.Center(
        child: pw.Text(
          'No ${report.shelfName.toLowerCase()} usage logged for '
          '${report.periodLabel}.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
    );
  }

  static pw.Widget _table(MonthlyReport report) {
    final showAdded = report.hasAdditions;
    final header = _headerRow(report, showAdded);

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        if (showAdded) ...{
          1: const pw.FlexColumnWidth(1.4),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.4),
          4: const pw.FlexColumnWidth(1.4),
          5: const pw.FlexColumnWidth(1.4),
        } else ...{
          1: const pw.FlexColumnWidth(1.4),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.4),
        },
      },
      children: [
        header,
        ...report.rows.map((row) => _dataRow(row, showAdded)),
      ],
    );
  }

  static pw.TableRow _headerRow(MonthlyReport report, bool showAdded) {
    final style = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.4,
      color: PdfColors.grey800,
    );
    return pw.TableRow(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 1.1),
        ),
      ),
      children: [
        _headCell('NAME', style, alignLeft: true),
        if (showAdded) ...[
          _headCell('WE HAVE', style),
          _headCell('ADDED', style),
          _headCell('NOW WE HAVE', style),
          _headCell('USED', style),
        ] else ...[
          _headCell('WE HAVE', style),
          _headCell('USED', style),
        ],
        _headCell('LEFT', style),
      ],
    );
  }

  static pw.Widget _headCell(
    String text,
    pw.TextStyle style, {
    bool alignLeft = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
        style: style,
      ),
    );
  }

  static pw.TableRow _dataRow(ReportRow row, bool showAdded) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                row.name,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (row.subtitle.isNotEmpty)
                pw.Text(
                  row.subtitle,
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey600,
                  ),
                ),
            ],
          ),
        ),
        if (showAdded) ...[
          _number(row.weHave, row.unit),
          _number(row.added, row.unit),
          _number(row.nowHave, row.unit),
          _number(row.used, row.unit, prefix: '-'),
        ] else ...[
          _number(row.weHave, row.unit),
          _number(row.used, row.unit, prefix: '-'),
        ],
        _number(row.left, row.unit, bold: true),
      ],
    );
  }

  static pw.Widget _number(
    double value,
    String unit, {
    String prefix = '',
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        '$prefix${formatQuantity(value)} $unit',
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
