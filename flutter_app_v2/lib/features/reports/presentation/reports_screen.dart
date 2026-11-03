import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/models.dart';
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

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final report = buildMonthlyReport(
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
          _ReportTable(report: report),
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
      ],
    );
  }

  Future<void> _export(InventoryState state) async {
    setState(() => _exporting = true);
    try {
      final reports = [
        for (final kind in ItemKind.values)
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
              style: context.label.copyWith(fontSize: 8.5, letterSpacing: .9),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final showAdded = report.hasAdditions;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: lab.ink, width: 1.2)),
          ),
          child: Row(
            children: [
              Expanded(flex: 4, child: _Head('NAME')),
              if (showAdded) ...[
                Expanded(flex: 14, child: _Head('WE HAVE')),
                Expanded(flex: 14, child: _Head('ADDED')),
                Expanded(flex: 14, child: _Head('NOW')),
              ] else
                Expanded(flex: 14, child: _Head('WE HAVE')),
              Expanded(flex: 14, child: _Head('USED')),
              Expanded(flex: 14, child: _Head('LEFT')),
            ],
          ),
        ),
        for (final row in report.rows)
          _ReportRowView(row: row, showAdded: showAdded),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: context.label.copyWith(fontSize: 8, letterSpacing: .7),
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
                  style: context.itemName.copyWith(fontSize: 13.5),
                ),
                if (row.subtitle.isNotEmpty)
                  Text(
                    row.subtitle,
                    style: context.formula.copyWith(
                      fontSize: 11.5,
                      color: lab.soft,
                    ),
                  ),
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
          fontSize: 11.5,
          color: color ?? lab.ink,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}
