import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../inventory/domain/models.dart';
import '../domain/asset_reports.dart';
import '../domain/lab_profile.dart';
import '../domain/report_range.dart';
import '../domain/report_stats.dart';
import '../domain/runout.dart';

/// One activity line, already resolved to names so the PDF layer needs no
/// inventory lookups.
class ReportPdfLog {
  const ReportPdfLog({
    required this.at,
    required this.item,
    required this.action,
    required this.amount,
    required this.note,
  });

  final DateTime at;
  final String item;
  final String action;
  final String amount;
  final String note;
}

/// One summary usage row for the main consumption table.
class ReportPdfUsageRow {
  const ReportPdfUsageRow({
    required this.name,
    required this.formulaOrCategory,
    required this.unit,
    required this.startStock,
    required this.used,
    required this.added,
    required this.left,
    required this.pct,
  });

  final String name;
  final String formulaOrCategory;
  final String unit;
  final double startStock;
  final double used;
  final double added;
  final double left;
  final double pct;
}

/// Everything the branded report needs (REPORT-06).
class ReportPdfInput {
  const ReportPdfInput({
    required this.profile,
    required this.kind,
    required this.range,
    required this.trend,
    required this.logs,
    required this.runOut,
    required this.damage,
    required this.healthyItems,
    required this.totalItems,
    this.usageRows = const [],
    this.itemsUsedCount,
    this.restockedCount,
    this.criticalCount,
    this.logo,
    this.expiry,
    this.loans,
    this.services,
    this.generatedAt,
  });

  final LabProfile profile;
  final Uint8List? logo;
  final ItemKind kind;
  final ReportRange range;
  final TrendComparison trend;
  final List<ReportPdfLog> logs;
  final List<ReportPdfUsageRow> usageRows;
  final int? itemsUsedCount;
  final int? restockedCount;
  final int? criticalCount;
  final RunOutReport runOut;
  final DamageReport damage;
  final ExpiryReport? expiry;
  final LoanReport? loans;
  final ServiceReport? services;
  final int healthyItems;
  final int totalItems;

  /// Stamp in the footer; now when omitted.
  final DateTime? generatedAt;

  String get title =>
      '${kind == ItemKind.chemical ? 'Chemicals' : 'Apparatus'} Consumption Report';
}

const _ink = PdfColor.fromInt(0xFF1A1A1A);
const _muted = PdfColor.fromInt(0xFF666666);
const _lightMuted = PdfColor.fromInt(0xFF888888);
const _rule = PdfColor.fromInt(0xFFE0E0E0);
const _band = PdfColor.fromInt(0xFFF9FAFB);
const _green = PdfColor.fromInt(0xFF5E8C5A);
const _red = PdfColor.fromInt(0xFFB23A2E);
const _amber = PdfColor.fromInt(0xFFD89A3E);

/// Builds the A4 consumption report: branded header, 3 KPI cards,
/// and the consumption table. The increase column is added only when
/// something was restocked; otherwise the original columns stay.
Future<Uint8List> buildReportPdf(ReportPdfInput input) async {
  final generated = input.generatedAt ?? DateTime.now();
  final profile = input.profile;
  final logo = input.logo == null ? null : pw.MemoryImage(input.logo!);
  final day = DateFormat('d MMM yyyy');
  final stamp = DateFormat('d MMM yyyy, HH:mm');
  final labName = profile.name.trim().isEmpty
      ? 'Lab Wizard'
      : profile.name.trim();
  final contactLines = [
    if (profile.contact.trim().isNotEmpty) profile.contact.trim(),
    ...profile.address
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty),
  ];

  // Header matching standard lab report layout
  pw.Widget header(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 12),
    margin: const pw.EdgeInsets.only(bottom: 16),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 2.0)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            height: 42,
            width: 42,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                labName,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                contactLines.isNotEmpty
                    ? contactLines.join(' - ')
                    : 'bench inventory',
                style: const pw.TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              input.title,
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Period: ${input.range.label} - Generated: ${stamp.format(generated)}',
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
          ],
        ),
      ],
    ),
  );

  // Footer with clean page number and generation stamp (no cryptic asterisks)
  pw.Widget footer(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    margin: const pw.EdgeInsets.only(top: 14),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.8)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Lab Wizard - ${input.title}',
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    ),
  );

  pw.Widget note(String text) =>
      pw.Text(text, style: const pw.TextStyle(fontSize: 9, color: _muted));

  // KPI Card
  pw.Widget kpiBox(String value, String label, PdfColor color) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _ink, width: 1.5),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            label.toUpperCase(),
            style: const pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ),
  );

  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.Alignment>? alignments,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    ),
    cellStyle: const pw.TextStyle(fontSize: 8.5, color: _ink),
    headerAlignment: pw.Alignment.centerLeft,
    headerDecoration: const pw.BoxDecoration(color: _band),
    rowDecoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.5)),
    ),
    border: null,
    cellAlignments: alignments ?? const {},
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
  );

  final expiry = input.expiry;
  final loans = input.loans;
  final services = input.services;
  final estimates = input.runOut.estimates.take(10).toList();

  // Usage stats for KPI boxes. Same cards as the original report.
  final usageRows = input.usageRows;
  final showIncrease = usageRows.any((row) => row.added > 0);
  final itemsUsedCount =
      input.itemsUsedCount ?? usageRows.where((row) => row.used > 0).length;
  final totalUsesCount = input.logs
      .where(
        (log) =>
            log.action == InventoryAction.consume.name ||
            log.action == InventoryAction.breakage.name,
      )
      .length;
  final lowStockCount =
      input.criticalCount ?? usageRows.where((row) => row.pct < 50).length;

  pw.Widget usageHead(String label, {bool left = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: pw.Align(
      alignment: left ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
      child: pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: _muted,
          letterSpacing: 0.5,
        ),
      ),
    ),
  );

  pw.Widget usageQty(
    String value, {
    PdfColor color = _muted,
    bool emphasize = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    ),
  );

  final document = pw.Document(
    title: '${input.title} - ${input.range.dates}',
    author: labName,
    creator: 'Lab Wizard',
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
      header: header,
      footer: footer,
      build: (context) => [
        // 1. KPI Boxes Row
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Row(
            children: [
              kpiBox('$itemsUsedCount', 'Items consumed', _ink),
              kpiBox(
                totalUsesCount > 0 ? '$totalUsesCount' : '${usageRows.length}',
                'Consumption events',
                _green,
              ),
              kpiBox('$lowStockCount', 'Low stock items', _red),
            ],
          ),
        ),

        // Used items, plus restocked items when the increase column is shown.
        if (usageRows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 24),
            child: pw.Center(
              child: note(
                'No ${input.kind == ItemKind.chemical ? 'chemical' : 'apparatus'} consumption logged for ${input.range.label}.',
              ),
            ),
          )
        else
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(3.4),
              for (var column = 1; column < (showIncrease ? 5 : 4); column++)
                column: const pw.FlexColumnWidth(1.6),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _ink, width: 2.0),
                  ),
                ),
                children: [
                  usageHead('NAME', left: true),
                  usageHead('START STOCK'),
                  if (showIncrease) usageHead('INCREASE'),
                  usageHead('CONSUMED'),
                  usageHead('REMAINING'),
                ],
              ),
              for (final row in usageRows)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _rule, width: 0.6),
                    ),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            row.name,
                            style: pw.TextStyle(
                              fontSize: 10.5,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                          if (row.formulaOrCategory.isNotEmpty) ...[
                            pw.SizedBox(height: 1),
                            pw.Text(
                              row.formulaOrCategory,
                              style: const pw.TextStyle(
                                fontSize: 8.5,
                                color: _lightMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    usageQty('${formatQuantity(row.startStock)} ${row.unit}'),
                    if (showIncrease)
                      usageQty(
                        row.added > 0
                            ? '+${formatQuantity(row.added)} ${row.unit}'
                            : '0 ${row.unit}',
                        color: row.added > 0 ? _green : _muted,
                        emphasize: row.added > 0,
                      ),
                    usageQty(
                      '-${formatQuantity(row.used)} ${row.unit}',
                      color: _amber,
                      emphasize: true,
                    ),
                    usageQty(
                      '${formatQuantity(row.left)} ${row.unit}',
                      color: _ink,
                      emphasize: true,
                    ),
                  ],
                ),
            ],
          ),
        if (showIncrease) ...[
          pw.SizedBox(height: 8),
          note(
            'Start stock + increase − consumed = remaining. '
            'Only used and restocked items are listed.',
          ),
        ],

        // 3. Run-out estimates
        if (estimates.isNotEmpty) ...[
          heading('Run-out estimates'),
          table(
            const ['Item', 'Left', 'Runs out', 'Basis'],
            [
              for (final estimate in estimates)
                [
                  estimate.name,
                  '${formatQuantity(estimate.quantity)} ${estimate.unit}',
                  estimate.headline,
                  '${estimate.entries} uses, '
                      '${formatQuantity(estimate.consumedTotal)} '
                      '${estimate.unit} in ${estimate.historyDays} days',
                ],
            ],
          ),
          if (input.runOut.withoutEstimate > 0) ...[
            pw.SizedBox(height: 4),
            note(input.runOut.gapSummary),
          ],
        ],

        // 5. Expiry
        if (expiry != null && !expiry.isEmpty) ...[
          heading('Expiry'),
          table(
            const ['Chemical', 'Expiry date', 'Status'],
            [
              for (final row in [...expiry.expired, ...expiry.expiringSoon])
                [
                  row.chemical.name,
                  day.format(row.chemical.expiryDate!),
                  row.state == ExpiryState.expired
                      ? 'expired ${relativeDays(row.days)}'
                      : relativeDays(row.days),
                ],
            ],
          ),
        ],

        // 6. Damage in this range
        if (!input.damage.isEmpty) ...[
          heading('Damage in this range'),
          table(
            const ['Item', 'Incidents', 'Amount', 'Last'],
            [
              for (final row in input.damage.rows)
                [
                  row.name,
                  '${row.incidents}',
                  '${formatQuantity(row.amount)} ${row.unit}'.trim(),
                  day.format(row.lastAt.toLocal()),
                ],
            ],
            alignments: const {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
            },
          ),
        ],

        // 7. Overdue loans
        if (loans != null && !loans.isEmpty) ...[
          heading('Overdue loans'),
          table(
            const ['Apparatus', 'Person', 'Out', 'Due', 'Overdue'],
            [
              for (final loan in loans.overdue)
                [
                  loan.apparatusName,
                  loan.checkout.person,
                  formatQuantity(loan.checkout.outstanding),
                  day.format(loan.checkout.dueAt!.toLocal()),
                  loan.when,
                ],
            ],
          ),
        ],

        // 8. Maintenance and calibration
        if (services != null && !services.isEmpty) ...[
          heading('Maintenance and calibration'),
          table(
            const ['Task', 'Apparatus', 'Kind', 'Due', 'Status'],
            [
              for (final row in services.due)
                [
                  row.service.displayTitle,
                  row.apparatusName,
                  row.service.kind.label,
                  day.format(row.service.dueAt!.toLocal()),
                  row.when,
                ],
            ],
          ),
          pw.SizedBox(height: 4),
          note(
            '${services.openTasks} open tasks - ${services.completedInRange} '
            'completed in this range.',
          ),
        ],
      ],
    ),
  );
  return document.save();
}
