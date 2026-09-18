import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ItemKind _kind = ItemKind.chemical;
  bool _exporting = false;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final logs = state.logs
        .where(
          (log) =>
              log.itemType == _kind &&
              log.loggedAt.toLocal().year == _month.year &&
              log.loggedAt.toLocal().month == _month.month,
        )
        .toList();
    final consumed = logs
        .where((log) => log.action == InventoryAction.consume)
        .length;
    final restocked = logs
        .where((log) => log.action == InventoryAction.restock)
        .length;
    final broken = logs
        .where((log) => log.action == InventoryAction.breakage)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(54, 18, 20, 32),
      children: [
        const PageHeading('monthly report'),
        const SizedBox(height: 2),
        NotebookCard(
          tape: NotebookTape.yellow,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Caveat',
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: _isCurrentMonth
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.science_outlined, size: 19),
            const SizedBox(width: 4),
            NotebookFilterWord(
              label: 'chemicals',
              selected: _kind == ItemKind.chemical,
              onTap: () => setState(() => _kind = ItemKind.chemical),
              fontSize: 21,
            ),
            const SizedBox(width: 20),
            const Icon(Icons.precision_manufacturing_outlined, size: 19),
            const SizedBox(width: 4),
            NotebookFilterWord(
              label: 'apparatus',
              selected: _kind == ItemKind.apparatus,
              onTap: () => setState(() => _kind = ItemKind.apparatus),
              fontSize: 21,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _ReportMetric(
                label: 'usage actions',
                value: consumed,
                color: LabColors.amber,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ReportMetric(
                label: 'restocks',
                value: restocked,
                color: LabColors.green,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ReportMetric(
                label: 'damage',
                value: broken,
                color: LabColors.marginRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const PageHeading('activity by day'),
        NotebookCard(
          child: _MonthChart(month: _month, logs: logs),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: logs.isEmpty || _exporting
              ? null
              : () => _export(state, logs),
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_exporting ? 'Preparing PDF…' : 'Share PDF report'),
        ),
        const SizedBox(height: 24),
        const PageHeading('activity log'),
        if (logs.isEmpty)
          const EmptyNotebookState(
            icon: Icons.query_stats,
            title: 'no activity this month',
            message: 'Choose another month or start logging inventory actions.',
          )
        else
          ...logs.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: StaggerIn(
                index: entry.key,
                child: _ReportLogRow(log: entry.value, state: state),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _export(InventoryState state, List<ConsumptionLog> logs) async {
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdf(state, logs);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'lab-wizard-${DateFormat('yyyy-MM').format(_month)}.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _buildPdf(
    InventoryState state,
    List<ConsumptionLog> logs,
  ) async {
    final document = pw.Document(
      title: 'Lab Wizard ${DateFormat('MMMM yyyy').format(_month)} report',
      author: 'Lab Wizard',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Text(
            'Lab Wizard',
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            '${_kind == ItemKind.chemical ? 'Chemical' : 'Apparatus'} report — ${DateFormat('MMMM yyyy').format(_month)}',
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Item', 'Action', 'Amount', 'Note'],
            data: logs
                .map(
                  (log) => [
                    DateFormat('dd MMM').format(log.loggedAt.toLocal()),
                    _itemName(state, log),
                    log.action.name,
                    formatQuantity(log.amount),
                    log.note,
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
        ],
      ),
    );
    return document.save();
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NotebookCard(
      accent: color,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedQuantity(
            value.toDouble(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: context.mutedInkColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MonthChart extends StatelessWidget {
  const _MonthChart({required this.month, required this.logs});

  final DateTime month;
  final List<ConsumptionLog> logs;

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final groups = <int, int>{};
    for (final log in logs) {
      groups.update(
        log.loggedAt.toLocal().day,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final maxY = groups.values
        .fold<int>(1, (max, value) => value > max ? value : max)
        .toDouble();
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY + 1,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 5,
                getTitlesWidget: (value, _) => Text(
                  value.toInt() == 0 ? '' : '${value.toInt()}',
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
          ),
          barGroups: List.generate(days, (index) {
            final day = index + 1;
            return BarChartGroupData(
              x: day,
              barRods: [
                BarChartRodData(
                  toY: (groups[day] ?? 0).toDouble(),
                  width: 5,
                  color: LabColors.marginRed,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 500),
      ),
    );
  }
}

class _ReportLogRow extends StatelessWidget {
  const _ReportLogRow({required this.log, required this.state});

  final ConsumptionLog log;
  final InventoryState state;

  @override
  Widget build(BuildContext context) {
    return NotebookCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              DateFormat('dd\nMMM').format(log.loggedAt.toLocal()),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _itemName(state, log),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  log.action.name,
                  style: TextStyle(color: context.mutedInkColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            formatQuantity(log.amount),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

String _itemName(InventoryState state, ConsumptionLog log) {
  if (log.itemType == ItemKind.chemical) {
    return state.chemicals
            .where((item) => item.id == log.itemId)
            .map((item) => item.name)
            .firstOrNull ??
        'Removed chemical';
  }
  return state.apparatus
          .where((item) => item.id == log.itemId)
          .map((item) => item.name)
          .firstOrNull ??
      'Removed apparatus';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
