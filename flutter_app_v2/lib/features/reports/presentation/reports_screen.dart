import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/models.dart';
import '../data/closed_months.dart';
import '../data/report_pdf.dart';
import '../domain/monthly_report.dart';

/// The monthly sheet, on screen and on paper.
///
/// What is drawn here is what the PDF contains — the same rows, the same
/// columns, the same order — so nobody has to wonder whether the printout
/// matches what they were looking at.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ItemKind _kind = ItemKind.chemical;
  bool _exporting = false;

  /// Cards unless the reader asks for columns: six numbers do not fit a phone.
  bool _asCards = true;

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final closed = ref.watch(closedMonthsProvider)[ClosedMonth.keyFor(_month)];
    // A closed month shows what was signed off, not a fresh calculation.
    final report = closed != null
        ? frozenReport(closed, _kind, _month)
        : buildMonthlyReport(
            kind: _kind,
            chemicals: state.chemicals,
            apparatus: state.apparatus,
            logs: state.logs,
            month: _month,
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reports',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.05,
                  letterSpacing: -1.2,
                  fontWeight: FontWeight.w600,
                  color: lab.ink,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_left, size: 22),
            ),
            Text(
              DateFormat('MMM yyyy').format(_month),
              style: context.figure.copyWith(fontSize: 14),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right, size: 22),
            ),
          ],
        ),
        if (closed != null)
          _ClosedNote(
            closedAt: closed.closedAt,
            onReopen: () => _reopen(closed),
          ),
        const SizedBox(height: 12),
        _ShelfTabs(
          kind: _kind,
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: 14),
        _KpiStrip(report: report),
        const SizedBox(height: 16),
        if (report.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 34),
            child: Column(
              children: [
                Text(
                  'Nothing logged',
                  style: context.itemName.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'No ${report.shelfName.toLowerCase()} were used or restocked '
                  'in ${report.periodLabel}.',
                  textAlign: TextAlign.center,
                  style: context.aside.copyWith(fontSize: 16),
                ),
              ],
            ),
          )
        else
          _ReportTable(
            report: report,
            asCards: _asCards,
            onToggle: () => setState(() => _asCards = !_asCards),
          ),
        const SizedBox(height: 18),
        if (!report.isEmpty)
          Text(report.footnote, style: context.aside.copyWith(fontSize: 15)),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _exporting ? null : () => _export(state),
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share, size: 18),
          label: Text(_exporting ? 'Preparing…' : 'Share this month as PDF'),
        ),
        const SizedBox(height: 8),
        Text(
          'The PDF has both shelves, chemicals first, each starting on its own '
          'page.',
          textAlign: TextAlign.center,
          style: context.aside.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 16),
        if (closed == null && !report.isEmpty)
          OutlinedButton.icon(
            onPressed: () => _close(report, state),
            icon: const Icon(Icons.lock_outline, size: 17),
            label: const Text('Close this month'),
          ),
        if (closed == null && !report.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Closing keeps a copy of these numbers, so editing an old entry '
              'later cannot change this copy. It is saved only on this device; '
              'share a PDF to keep a copy elsewhere.',
              textAlign: TextAlign.center,
              style: context.aside.copyWith(fontSize: 14),
            ),
          ),
      ],
    );
  }

  Future<void> _close(MonthlyReport report, InventoryState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Close ${report.periodLabel}?'),
        content: const Text(
          'The numbers stop changing. You can reopen the month if something '
          'turns out to be wrong. This copy is saved only on this device, '
          'not shared with other devices. Share a PDF for safekeeping.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close it'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final reports = [
      for (final kind in ItemKind.values)
        buildMonthlyReport(
          kind: kind,
          chemicals: state.chemicals,
          apparatus: state.apparatus,
          logs: state.logs,
          month: _month,
        ),
    ];
    try {
      await ref.read(closedMonthsProvider.notifier).close(reports, _month);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save the closed report on this device.'),
      ));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${report.periodLabel} closed')),
    );
  }

  Future<void> _reopen(ClosedMonth closed) async {
    try {
      await ref.read(closedMonthsProvider.notifier).reopen(_month);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not reopen the report on this device.'),
      ));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${closed.monthKey} reopened')),
    );
  }

  Future<void> _export(InventoryState state) async {
    setState(() => _exporting = true);
    try {
      final closed = await ref.read(closedMonthsProvider.notifier).closedFor(_month);
      final reports = [
        for (final kind in ItemKind.values)
          if (closed != null)
            frozenReport(closed, kind, _month)
          else
            buildMonthlyReport(
              kind: kind,
              chemicals: state.chemicals,
              apparatus: state.apparatus,
              logs: state.logs,
              month: _month,
            ),
      ]..removeWhere((report) => report.isEmpty);

      if (reports.isEmpty) {
        final label = DateFormat('MMMM yyyy').format(_month);
        throw StateError('Nothing to report for $label.');
      }

      final bytes = await ReportPdf.build(
        reports: reports,
        generatedAt: DateTime.now(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'lab-wizard-${DateFormat('yyyy-MM').format(_month)}.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _ShelfTabs extends StatelessWidget {
  const _ShelfTabs({required this.kind, required this.onChanged});

  final ItemKind kind;
  final ValueChanged<ItemKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Row(
      children: [
        for (final value in ItemKind.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: kind == value,
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(value),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kind == value ? lab.ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: kind == value ? lab.ink : lab.hair,
                      ),
                    ),
                    child: Text(
                      value == ItemKind.chemical ? 'CHEMICALS' : 'APPARATUS',
                      style: context.label.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.1,
                        color: kind == value ? lab.bone : lab.soft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Kpi(value: '${report.itemsConsumed}', label: 'items consumed'),
        const SizedBox(width: 8),
        _Kpi(value: '${report.events}', label: 'events'),
        const SizedBox(width: 8),
        _Kpi(
          value: '${report.lowStockCount}',
          label: 'low stock',
          warn: report.lowStockCount > 0,
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.label, this.warn = false});

  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          border: Border.all(color: lab.hair),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                color: warn ? lab.clay : lab.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              style: context.label.copyWith(
                fontSize: LabType.micro,
                letterSpacing: .9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month, as cards or as a table.
///
/// Cards are the default: six numeric columns will not fit a phone, and
/// squeezing them to nine pixels is how a report becomes unreadable. The table
/// scrolls sideways for anyone who wants the columns lined up, and the PDF
/// keeps the full column layout because paper has room.
class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.report,
    required this.asCards,
    required this.onToggle,
  });

  final MonthlyReport report;
  final bool asCards;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              asCards ? 'BY ITEM' : 'TABLE',
              style: context.label.copyWith(fontSize: LabType.micro),
            ),
            const Spacer(),
            TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 34),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                asCards ? 'See as table' : 'See as cards',
                style: context.aside.copyWith(
                  fontSize: LabType.small,
                  color: lab.soft,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (asCards)
          for (final row in report.rows)
            _ReportCard(row: row, showAdded: report.hasAdditions)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(
                MediaQuery.sizeOf(context).width - 32,
                520,
              ),
              child: Column(
                children: [
                  _TableHead(showAdded: report.hasAdditions),
                  for (final row in report.rows)
                    _ReportRowView(
                      row: row,
                      showAdded: report.hasAdditions,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One item, written as the sum it is rather than as a row of columns.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.row, required this.showAdded});

  final ReportRow row;
  final bool showAdded;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final unit = row.unit;
    String quantity(double value) => '${formatQuantity(value)} $unit';
    final line = showAdded
        ? '${quantity(row.weHave)} + ${quantity(row.added)} '
              '= ${quantity(row.nowHave)}'
        : 'We have ${quantity(row.weHave)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: lab.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.name, style: context.itemName),
              ),
              Text(
                quantity(row.left),
                style: context.figure.copyWith(
                  fontSize: LabType.small + 1,
                  color: row.left <= 0 ? lab.berry : lab.ink,
                ),
              ),
            ],
          ),
          if (row.subtitle.isNotEmpty)
            Text(row.subtitle, style: context.formula),
          const SizedBox(height: 6),
          Text(
            '$line − ${quantity(row.used)} used',
            style: context.aside.copyWith(
              fontSize: LabType.small + 1,
              color: lab.soft,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead({required this.showAdded});

  final bool showAdded;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lab.ink, width: 1.2)),
      ),
      child: Row(
        children: [
          const Expanded(flex: 4, child: _Head('NAME', alignLeft: true)),
          if (showAdded) ...[
            const Expanded(flex: 14, child: _Head('WE HAVE')),
            const Expanded(flex: 14, child: _Head('ADDED')),
            const Expanded(flex: 14, child: _Head('NOW')),
          ] else
            const Expanded(flex: 14, child: _Head('WE HAVE')),
          const Expanded(flex: 14, child: _Head('USED')),
          const Expanded(flex: 14, child: _Head('LEFT')),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text, {this.alignLeft = false});

  final String text;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignLeft ? TextAlign.left : TextAlign.right,
      style: context.label.copyWith(
        fontSize: LabType.micro,
        letterSpacing: .7,
      ),
    );
  }
}

class _ReportRowView extends StatelessWidget {
  const _ReportRowView({required this.row, required this.showAdded});

  final ReportRow row;
  final bool showAdded;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lab.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: context.itemName.copyWith(fontSize: LabType.small + 1),
                ),
                if (row.subtitle.isNotEmpty)
                  Text(row.subtitle, style: context.formula),
              ],
            ),
          ),
          if (showAdded) ...[
            _Cell('${formatQuantity(row.weHave)} ${row.unit}', flex: 14),
            _Cell('${formatQuantity(row.added)} ${row.unit}', flex: 14),
            _Cell('${formatQuantity(row.nowHave)} ${row.unit}', flex: 14),
          ] else
            _Cell('${formatQuantity(row.weHave)} ${row.unit}', flex: 14),
          _Cell(
            '−${formatQuantity(row.used)} ${row.unit}',
            flex: 14,
            color: lab.clay,
          ),
          _Cell(
            '${formatQuantity(row.left)} ${row.unit}',
            flex: 14,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    required this.flex,
    this.color,
    this.bold = false,
  });

  final String text;
  final int flex;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: context.figure.copyWith(
          fontSize: LabType.small,
          color: color ?? lab.ink,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// Shown instead of the close button when a month has been signed off.
class _ClosedNote extends StatelessWidget {
  const _ClosedNote({required this.closedAt, required this.onReopen});

  final DateTime closedAt;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
      decoration: BoxDecoration(
        color: lab.wash(lab.sage),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: lab.wash(lab.sage, .35)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 15, color: lab.sage),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Closed ${DateFormat('d MMM').format(closedAt)} — these are the '
              'numbers saved on this device only. Share a PDF for safekeeping.',
              style: context.aside.copyWith(
                fontSize: LabType.small,
                color: lab.sage,
              ),
            ),
          ),
          TextButton(
            onPressed: onReopen,
            style: TextButton.styleFrom(minimumSize: const Size(48, 32)),
            child: Text(
              'Reopen',
              style: context.label.copyWith(
                fontSize: LabType.micro,
                color: lab.sage,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
