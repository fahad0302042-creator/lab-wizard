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

/// One summary usage row for the main usage table (matching the web app report format).
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
      '${kind == ItemKind.chemical ? 'Chemicals' : 'Apparatus'} Usage Report';
}

const _ink = PdfColor.fromInt(0xFF1A1A1A);
const _muted = PdfColor.fromInt(0xFF666666);
const _lightMuted = PdfColor.fromInt(0xFF888888);
const _rule = PdfColor.fromInt(0xFFE0E0E0);
const _band = PdfColor.fromInt(0xFFF9FAFB);
const _green = PdfColor.fromInt(0xFF5E8C5A);
const _red = PdfColor.fromInt(0xFFB23A2E);
const _amber = PdfColor.fromInt(0xFFD89A3E);

/// Builds the A4 report: matching the web app's clean Usage Report format
/// (header, 3 KPI boxes, Name/Stock/−Used/=Left table, * and ** indicators,
/// and optional activity breakdown).
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

  // Header matching the web app report format
  pw.Widget header(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 12),
    margin: const pw.EdgeInsets.only(bottom: 16),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: _ink, width: 2.0),
      ),
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
                    ? contactLines.join(' · ')
                    : 'bench inventory',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: _muted,
                ),
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
              'Period: ${input.range.label}  ·  Generated: ${stamp.format(generated)}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: _muted,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // Footer with legend and page number
  pw.Widget footer(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    margin: const pw.EdgeInsets.only(top: 14),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.8)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            pw.Text(
              '* ',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _red,
              ),
            ),
            pw.Text(
              'below 50% remaining    ',
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
            pw.Text(
              '** ',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _red,
              ),
            ),
            pw.Text(
              'below 20% remaining — reorder',
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          ],
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

  // KPI Box matching web app's KpiBox
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

  // Usage stats for KPI boxes
  final usageRows = input.usageRows;
  final itemsUsedCount = input.itemsUsedCount ??
      usageRows.where((r) => r.used > 0).length;
  final restockedCount = input.restockedCount ??
      usageRows.where((r) => r.added > 0).length;
  final criticalCount = input.criticalCount ??
      (input.totalItems - input.healthyItems);

  final document = pw.Document(
    title: '${input.title} — ${input.range.dates}',
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
              kpiBox('$itemsUsedCount', 'Items used', _ink),
              kpiBox('$restockedCount', 'Restocked', _green),
              kpiBox('$criticalCount', 'Critical', _red),
            ],
          ),
        ),

        // 2. Primary Usage Report Table (matches web app format)
        if (usageRows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 20),
            child: pw.Center(
              child: note(
                'No ${input.kind == ItemKind.chemical ? 'chemical' : 'apparatus'} usage logged for ${input.range.label}.',
              ),
            ),
          )
        else
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(3.8),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(2.0),
            },
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _ink, width: 2.0),
                  ),
                ),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: pw.Text(
                      'NAME',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'STOCK',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _muted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        '− USED',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _muted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        '= LEFT',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _muted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Item rows
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
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          '${formatQuantity(row.startStock)} ${row.unit}',
                          style: const pw.TextStyle(
                            fontSize: 9.5,
                            color: _muted,
                          ),
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          row.used > 0 ? '−${formatQuantity(row.used)}' : '—',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: row.used > 0 ? _amber : _muted,
                          ),
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              '${formatQuantity(row.left)} ${row.unit}',
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                            if (row.pct < 20)
                              pw.Text(
                                ' **',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _red,
                                ),
                              )
                            else if (row.pct < 50)
                              pw.Text(
                                ' *',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _red,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

        // 3. Activity Log Table
        if (input.logs.isNotEmpty) ...[
          heading('Activity Log (${input.logs.length})'),
          table(
            const ['Date', 'Item', 'Action', 'Amount', 'Note'],
            [
              for (final log in input.logs)
                [
                  day.format(log.at.toLocal()),
                  log.item,
                  log.action,
                  log.amount,
                  log.note,
                ],
            ],
            alignments: const {3: pw.Alignment.centerRight},
          ),
        ],

        // 4. Run-out estimates
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
        if (expiry != null && expiry.isNotEmpty) ...[
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
        if (input.damage.isNotEmpty) ...[
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
        if (loans != null && loans.isNotEmpty) ...[
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
        if (services != null && services.isNotEmpty) ...[
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
            '${services.openTasks} open tasks · ${services.completedInRange} '
            'completed in this range.',
          ),
        ],
      ],
    ),
  );
  return document.save();
}
