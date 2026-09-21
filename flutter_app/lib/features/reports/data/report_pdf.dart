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
      '${kind == ItemKind.chemical ? 'Chemical' : 'Apparatus'} report';
}

const _ink = PdfColor.fromInt(0xFF1F2933);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _rule = PdfColor.fromInt(0xFFD1D5DB);
const _band = PdfColor.fromInt(0xFFF3F4F6);
const _accent = PdfColor.fromInt(0xFFB91C1C);

/// Builds the A4 report: branded header on every page, summary cards, the
/// activity table, run-out estimates and the attention views, page numbers
/// and a generation stamp in the footer.
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

  pw.Widget header(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 8),
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.8)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            height: 42,
            width: 42,
            margin: const pw.EdgeInsets.only(right: 10),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                labName,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              for (final line in contactLines)
                pw.Text(
                  line,
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted),
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
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.Text(
              input.range.label,
              style: const pw.TextStyle(fontSize: 9, color: _ink),
            ),
            pw.Text(
              input.range.dates,
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          ],
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    margin: const pw.EdgeInsets.only(top: 12),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Generated by Lab Wizard · ${stamp.format(generated)}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 11.5,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    ),
  );

  pw.Widget note(String text) =>
      pw.Text(text, style: const pw.TextStyle(fontSize: 9, color: _muted));

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
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.3)),
    ),
    border: null,
    cellAlignments: alignments ?? const {},
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
  );

  pw.Widget metric(String label, InventoryAction action) {
    final totals = input.trend.current.of(action);
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 8),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: _band,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${totals.count}',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: _accent,
              ),
            ),
            pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _ink)),
            if (totals.quantityLabel.isNotEmpty)
              pw.Text(
                totals.quantityLabel,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
            pw.Text(
              input.trend.describe(action),
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  final expiry = input.expiry;
  final loans = input.loans;
  final services = input.services;
  final estimates = input.runOut.estimates.take(10).toList();

  final document = pw.Document(
    title: '${input.title} — ${input.range.dates}',
    author: labName,
    creator: 'Lab Wizard',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 28),
      header: header,
      footer: footer,
      build: (context) => [
        heading('Summary'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            metric('usage actions', InventoryAction.consume),
            metric('restocks', InventoryAction.restock),
            metric('damage', InventoryAction.breakage),
          ],
        ),
        pw.SizedBox(height: 6),
        note(
          input.totalItems == 0
              ? 'No items on this shelf.'
              : '${input.healthyItems} of ${input.totalItems} items are '
                    'comfortably stocked. Changes are against the '
                    '${input.trend.previousLabel} '
                    '(${input.trend.previous.range.dates}).',
        ),
        heading('Activity (${input.logs.length})'),
        if (input.logs.isEmpty)
          note('No activity in this range.')
        else
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
        heading('Run-out estimates'),
        if (estimates.isEmpty)
          note(
            'No estimates yet: each needs $runOutMinEntries+ uses over '
            '$runOutMinSpanDays+ days within the last $runOutLookbackDays '
            'days.',
          )
        else ...[
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
        if (expiry != null) ...[
          heading('Expiry'),
          if (expiry.isEmpty)
            note('Nothing expired or expiring in the next 30 days.')
          else
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
        heading('Damage in this range'),
        if (input.damage.isEmpty)
          note('No damage recorded in this range.')
        else
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
        if (loans != null) ...[
          heading('Overdue loans'),
          if (loans.isEmpty)
            note(
              loans.openLoans == 0
                  ? 'Nothing is out on loan.'
                  : 'Nothing overdue; ${loans.openLoans} open loans.',
            )
          else
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
        if (services != null) ...[
          heading('Maintenance and calibration'),
          if (services.isEmpty)
            note('Nothing overdue or due in the next 14 days.')
          else
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
