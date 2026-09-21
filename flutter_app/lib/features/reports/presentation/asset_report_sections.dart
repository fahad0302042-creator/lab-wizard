import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../domain/asset_reports.dart';
import '../domain/report_range.dart';

/// Everything REPORT-04 knows about one shelf for the selected range.
class AssetReports {
  AssetReports.compute(
    InventoryState state, {
    required ReportRange range,
    required ItemKind kind,
    DateTime? now,
  }) : kind = kind,
       expiry = kind == ItemKind.chemical
           ? expiryReport(state.chemicals, now: now)
           : null,
       damage = damageReport(
         range,
         state.logs,
         kind: kind,
         nameOf: (id) => _nameOf(state, kind, id),
         unitOf: (id) => kind == ItemKind.apparatus
             ? 'pcs'
             : state.chemicals
                       .where((item) => item.id == id)
                       .map((item) => item.unit)
                       .firstOrNull ??
                   '',
       ),
       loans = kind == ItemKind.apparatus
           ? loanReport(
               state.checkouts,
               nameOf: (id) => _nameOf(state, kind, id),
               now: now,
             )
           : null,
       services = kind == ItemKind.apparatus
           ? serviceReport(
               state.services,
               range: range,
               nameOf: (id) => _nameOf(state, kind, id),
               now: now,
             )
           : null;

  final ItemKind kind;
  final ExpiryReport? expiry;
  final DamageReport damage;
  final LoanReport? loans;
  final ServiceReport? services;

  static String _nameOf(InventoryState state, ItemKind kind, String id) {
    if (kind == ItemKind.chemical) {
      return state.chemicals
              .where((item) => item.id == id)
              .map((item) => item.name)
              .firstOrNull ??
          'Removed chemical';
    }
    return state.apparatus
            .where((item) => item.id == id)
            .map((item) => item.name)
            .firstOrNull ??
        'Removed apparatus';
  }
}

/// The report-page cards for [reports], headings included.
List<Widget> assetReportSections(BuildContext context, AssetReports reports) {
  final expiry = reports.expiry;
  final loans = reports.loans;
  final services = reports.services;
  return [
    if (expiry != null) ...[
      const SizedBox(height: 24),
      const PageHeading('expiry'),
      _ExpiryCard(report: expiry),
    ],
    const SizedBox(height: 24),
    const PageHeading('damage'),
    _DamageCard(report: reports.damage),
    if (loans != null) ...[
      const SizedBox(height: 24),
      const PageHeading('overdue loans'),
      _LoansCard(report: loans),
    ],
    if (services != null) ...[
      const SizedBox(height: 24),
      const PageHeading('maintenance & calibration'),
      _ServicesCard(report: services),
    ],
  ];
}

class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({required this.report});

  final ExpiryReport report;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    final footer = [
      if (report.later > 0)
        '${report.later} expire${report.later == 1 ? 's' : ''} later',
      if (report.undated > 0) '${report.undated} without an expiry date',
    ].join(' · ');
    return NotebookCard(
      key: const Key('report-expiry'),
      tape: NotebookTape.yellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.isEmpty)
            Text(
              'Nothing expired or expiring in the next 30 days.',
              style: TextStyle(color: muted),
            ),
          for (final row in report.expired)
            _ReportLine(
              key: Key('expiry-${row.chemical.id}'),
              title: row.chemical.name,
              subtitle: row.when,
              trailing: 'expired',
              color: context.marginRedColor,
            ),
          for (final row in report.expiringSoon)
            _ReportLine(
              key: Key('expiry-${row.chemical.id}'),
              title: row.chemical.name,
              subtitle: row.when,
              trailing: relativeDays(row.days),
              color: context.lowColor,
            ),
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(footer, style: TextStyle(color: muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _DamageCard extends StatelessWidget {
  const _DamageCard({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    return NotebookCard(
      key: const Key('report-damage'),
      tape: NotebookTape.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.isEmpty)
            Text(
              'No damage recorded in this range.',
              style: TextStyle(color: muted),
            ),
          for (final row in report.rows)
            _ReportLine(
              key: Key('damage-${row.itemId}'),
              title: row.name,
              subtitle:
                  '${row.incidents} incident${row.incidents == 1 ? '' : 's'}'
                  ' · last ${DateFormat('d MMM').format(row.lastAt.toLocal())}',
              trailing: '${formatQuantity(row.amount)} ${row.unit}'.trim(),
              color: context.marginRedColor,
            ),
          if (!report.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${report.incidents} incident${report.incidents == 1 ? '' : 's'}'
              ' across ${report.rows.length} item'
              '${report.rows.length == 1 ? '' : 's'} in this range.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoansCard extends StatelessWidget {
  const _LoansCard({required this.report});

  final LoanReport report;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    return NotebookCard(
      key: const Key('report-loans'),
      tape: NotebookTape.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.isEmpty)
            Text(
              report.openLoans == 0
                  ? 'Nothing is out on loan.'
                  : 'Nothing overdue · ${report.openLoans} open loan'
                        '${report.openLoans == 1 ? '' : 's'}.',
              style: TextStyle(color: muted),
            ),
          for (final loan in report.overdue)
            _ReportLine(
              key: Key('loan-${loan.checkout.id}'),
              title: '${loan.apparatusName} · ${loan.checkout.person}',
              subtitle:
                  '${formatQuantity(loan.checkout.outstanding)} out · due '
                  '${DateFormat('d MMM').format(loan.checkout.dueAt!.toLocal())}',
              trailing: loan.when,
              color: context.marginRedColor,
            ),
          if (!report.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${report.overdue.length} of ${report.openLoans} open loan'
              '${report.openLoans == 1 ? '' : 's'} overdue.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard({required this.report});

  final ServiceReport report;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    return NotebookCard(
      key: const Key('report-services'),
      tape: NotebookTape.pink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.isEmpty)
            Text(
              'Nothing overdue or due in the next 14 days.',
              style: TextStyle(color: muted),
            ),
          for (final row in report.due)
            _ReportLine(
              key: Key('service-${row.service.id}'),
              title: '${row.service.displayTitle} · ${row.apparatusName}',
              subtitle:
                  '${row.service.kind.label} · '
                  '${DateFormat('d MMM').format(row.service.dueAt!.toLocal())}',
              trailing: row.when,
              color: row.overdue ? context.marginRedColor : context.lowColor,
            ),
          const SizedBox(height: 6),
          Text(
            '${report.openTasks} open task${report.openTasks == 1 ? '' : 's'}'
            ' · ${report.completedInRange} completed in this range.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.color,
    super.key,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.mutedInkColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
