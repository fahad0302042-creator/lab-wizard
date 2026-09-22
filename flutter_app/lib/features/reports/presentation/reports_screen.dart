import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/csv.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../data/report_pdf.dart';
import '../domain/csv_exports.dart';
import '../domain/report_range.dart';
import '../domain/report_stats.dart';
import '../domain/runout.dart';
import '../lab_profile_providers.dart';
import 'asset_report_sections.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRange _range = ReportRange.month(
    DateTime.now().year,
    DateTime.now().month,
  );
  ItemKind _kind = ItemKind.chemical;
  bool _exporting = false;

  void _choose(ReportRangeKind kind) {
    switch (kind) {
      case ReportRangeKind.last7:
        setState(() => _range = ReportRange.lastDays(7));
      case ReportRangeKind.last30:
        setState(() => _range = ReportRange.lastDays(30));
      case ReportRangeKind.month:
        final now = DateTime.now();
        setState(() => _range = ReportRange.month(now.year, now.month));
      case ReportRangeKind.custom:
        _pickCustomRange();
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: _range.start.isAfter(today) ? today : _range.start,
        end: _range.end.isAfter(today) ? today : _range.end,
      ),
      helpText: 'Report range (inclusive)',
      saveText: 'Use range',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = ReportRange.custom(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final logs = state.logs
        .where((log) => log.itemType == _kind && _range.contains(log.loggedAt))
        .toList();
    // REPORT-02: counts and unit-aware quantities next to the previous period.
    final trend = TrendComparison.compute(
      _range,
      state.logs,
      kind: _kind,
      unitOf: (itemId) =>
          state.chemicals
              .where((item) => item.id == itemId)
              .map((item) => item.unit)
              .firstOrNull ??
          '',
    );
    final itemStates = _kind == ItemKind.chemical
        ? state.chemicals.map((item) => item.stockState).toList()
        : state.apparatus.map((item) => item.stockState).toList();
    final healthyItems = itemStates
        .where((status) => status == StockState.healthy)
        .length;
    final healthRatio = itemStates.isEmpty
        ? 0.0
        : healthyItems / itemStates.length;
    final topUsage = _topUsage(state, logs, _kind);
    // REPORT-03: always judged on the last 90 days ending today, independent
    // of the range above, so a report about May does not "predict" the past.
    final runOut = _kind == ItemKind.chemical
        ? runOutReportForChemicals(state.chemicals, state.logs)
        : runOutReportForApparatus(state.apparatus, state.logs);
    // REPORT-04: expiry, damage, overdue loans, maintenance and calibration.
    final assets = AssetReports.compute(state, range: _range, kind: _kind);
    final usageRows = _computeUsageRows(state, logs, _kind);

    return ListView(
      padding: const EdgeInsets.fromLTRB(54, 18, 20, 32),
      children: [
        const PageHeading('report'),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final kind in ReportRangeKind.values)
              ChoiceChip(
                key: Key('report-range-${kind.name}'),
                label: Text(kind.label),
                selected: _range.kind == kind,
                onSelected: (_) => _choose(kind),
              ),
          ],
        ),
        const SizedBox(height: 8),
        NotebookCard(
          tape: NotebookTape.yellow,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              if (_range.kind == ReportRangeKind.month)
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => setState(() => _range = _range.previous),
                  icon: const Icon(Icons.chevron_left),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Report range ${_range.label}, ${_range.dates}',
                  child: InkWell(
                    key: const Key('report-range-label'),
                    onTap: _pickCustomRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            _range.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Caveat',
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${_range.dates} · ${_range.dayCount} '
                            'day${_range.dayCount == 1 ? '' : 's'}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.mutedInkColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_range.kind == ReportRangeKind.month)
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _range.isCurrentMonth()
                      ? null
                      : () => setState(() => _range = _range.nextMonth!),
                  icon: const Icon(Icons.chevron_right),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.science_outlined, size: 19),
                const SizedBox(width: 4),
                Flexible(
                  child: NotebookFilterWord(
                    label: 'chemicals',
                    selected: _kind == ItemKind.chemical,
                    onTap: () => setState(() => _kind = ItemKind.chemical),
                    fontSize: 21,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.precision_manufacturing_outlined, size: 19),
                const SizedBox(width: 4),
                Flexible(
                  child: NotebookFilterWord(
                    label: 'apparatus',
                    selected: _kind == ItemKind.apparatus,
                    onTap: () => setState(() => _kind = ItemKind.apparatus),
                    fontSize: 21,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Three tiles side by side; with large text or a narrow screen they
        // stack so the numbers are never squeezed (A11Y-02).
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth / scale >= 300 ? 3 : 1;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 9 * (columns - 1)) / columns;
            return Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                SizedBox(
                  width: width,
                  child: _ReportMetric(
                    key: const Key('metric-consume'),
                    label: 'usage actions',
                    action: InventoryAction.consume,
                    trend: trend,
                    color: LabColors.amber,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ReportMetric(
                    key: const Key('metric-restock'),
                    label: 'restocks',
                    action: InventoryAction.restock,
                    trend: trend,
                    color: LabColors.green,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ReportMetric(
                    key: const Key('metric-breakage'),
                    label: 'damage',
                    action: InventoryAction.breakage,
                    trend: trend,
                    color: LabColors.marginRed,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Change is against the ${trend.previousLabel} '
          '(${trend.previous.range.dates}); quantities are summed per unit '
          'and never mixed.',
          key: const Key('trend-note'),
          style: TextStyle(color: context.mutedInkColor, fontSize: 12),
        ),
        const SizedBox(height: 24),
        const PageHeading('stock health'),
        NotebookCard(
          tape: NotebookTape.blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    itemStates.isEmpty
                        ? '—'
                        : '${(healthRatio * 100).round()}%',
                    style: const TextStyle(
                      fontFamily: 'Caveat',
                      fontSize: 31,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      itemStates.isEmpty
                          ? 'No items on this shelf yet.'
                          : '$healthyItems of ${itemStates.length} items are comfortably stocked.',
                      style: TextStyle(color: context.mutedInkColor),
                    ),
                  ),
                ],
              ),
              if (itemStates.isNotEmpty) ...[
                const SizedBox(height: 10),
                StockBar(
                  progress: healthRatio,
                  status: healthRatio >= .8
                      ? StockState.healthy
                      : healthRatio > 0
                      ? StockState.low
                      : StockState.empty,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        const PageHeading('run-out estimates'),
        _RunOutSection(report: runOut),
        ...assetReportSections(context, assets),
        const SizedBox(height: 24),
        const PageHeading('consumption report'),
        NotebookCard(
          tape: NotebookTape.yellow,
          child: usageRows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No ${_kind == ItemKind.chemical ? 'chemical' : 'apparatus'} consumption logged for ${_range.label}.',
                      style: TextStyle(color: context.mutedInkColor),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final row in usageRows) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (row.formulaOrCategory.isNotEmpty)
                                    Text(
                                      row.formulaOrCategory,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.mutedInkColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '-${formatQuantity(row.used)} ${row.unit}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: LabColors.amber,
                                  ),
                                ),
                                Text(
                                  '${formatQuantity(row.left)} ${row.unit} left',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.mutedInkColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (row != usageRows.last)
                        const Divider(height: 1),
                    ],
                  ],
                ),
        ),
        if (topUsage.isNotEmpty) ...[
          const SizedBox(height: 24),
          PageHeading(
            _kind == ItemKind.chemical ? 'top used' : 'most reported',
          ),
          NotebookCard(
            tape: NotebookTape.green,
            child: Column(
              children: topUsage
                  .take(5)
                  .toList()
                  .asMap()
                  .entries
                  .map(
                    (entry) =>
                        _TopUsageRow(rank: entry.key + 1, summary: entry.value),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: logs.isEmpty || _exporting
              ? null
              : () => _export(state, logs, assets),
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_exporting ? 'Preparing PDF…' : 'Share PDF report'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('export-activity-csv'),
                onPressed: logs.isEmpty || _exporting
                    ? null
                    : () => _shareCsv(
                        name:
                            'lab-wizard-activity-${_kind.name}-'
                            '${_range.fileStem}.csv',
                        title: 'Lab Wizard activity ${_range.dates}',
                        csv: activityCsv(
                          range: _range,
                          kind: _kind,
                          logs: state.logs,
                          nameOf: (id) => _nameOfItem(state, _kind, id),
                          detailOf: (id) => _kind == ItemKind.chemical
                              ? state.chemicals
                                        .where((item) => item.id == id)
                                        .map((item) => item.formula)
                                        .firstOrNull ??
                                    ''
                              : state.apparatus
                                        .where((item) => item.id == id)
                                        .map((item) => item.category)
                                        .firstOrNull ??
                                    '',
                          unitOf: (id) =>
                              state.chemicals
                                  .where((item) => item.id == id)
                                  .map((item) => item.unit)
                                  .firstOrNull ??
                              '',
                        ),
                      ),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Activity CSV'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('export-inventory-csv'),
                onPressed: _exporting
                    ? null
                    : () => _shareCsv(
                        name:
                            'lab-wizard-${_kind == ItemKind.chemical ? 'chemicals' : 'apparatus'}-'
                            '${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
                        title:
                            'Lab Wizard '
                            '${_kind == ItemKind.chemical ? 'chemicals' : 'apparatus'}',
                        csv: _kind == ItemKind.chemical
                            ? chemicalsCsv(state.chemicals)
                            : apparatusCsv(state.apparatus),
                      ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Inventory CSV'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'CSV files open in Excel, LibreOffice and Sheets; cells that look '
          'like formulas are written as text so nothing in a note can run.',
          style: TextStyle(color: context.mutedInkColor, fontSize: 11),
        ),
      ],
    );
  }

  Future<void> _export(
    InventoryState state,
    List<ConsumptionLog> logs,
    AssetReports assets,
  ) async {
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdf(state, logs, assets);
      final kindTitle = _kind == ItemKind.chemical ? 'Chemicals' : 'Apparatus';
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Lab Wizard - $kindTitle Consumption Report - ${_range.label}.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// REPORT-05: writes [csv] to the cache directory and hands it to the
  /// share sheet (email, Drive, Files …).
  Future<void> _shareCsv({
    required String name,
    required String title,
    required String csv,
  }) async {
    setState(() => _exporting = true);
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(csvBytes(csv), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: title,
          text: title,
          files: [XFile(file.path, mimeType: 'text/csv', name: name)],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _buildPdf(
    InventoryState state,
    List<ConsumptionLog> logs,
    AssetReports assets,
  ) async {
    // REPORT-06: branded, paginated layout built from resolved data.
    final profileController = ref.read(labProfileProvider.notifier);
    final profile = ref.read(labProfileProvider);
    final logo = await profileController.logoBytes();
    final trend = TrendComparison.compute(
      _range,
      state.logs,
      kind: _kind,
      unitOf: (itemId) =>
          state.chemicals
              .where((item) => item.id == itemId)
              .map((item) => item.unit)
              .firstOrNull ??
          '',
    );
    final itemStates = _kind == ItemKind.chemical
        ? state.chemicals.map((item) => item.stockState)
        : state.apparatus.map((item) => item.stockState);
    final sorted = [...logs]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    final usageRows = _computeUsageRows(state, logs, _kind);

    return buildReportPdf(
      ReportPdfInput(
        profile: profile,
        logo: logo,
        kind: _kind,
        range: _range,
        trend: trend,
        usageRows: usageRows,
        logs: [
          for (final log in sorted)
            ReportPdfLog(
              at: log.loggedAt,
              item: _itemName(state, log),
              action: log.action.name,
              amount: '${formatQuantity(log.amount)} ${_unitOf(state, log)}'
                  .trim(),
              note: log.note,
            ),
        ],
        runOut: _kind == ItemKind.chemical
            ? runOutReportForChemicals(state.chemicals, state.logs)
            : runOutReportForApparatus(state.apparatus, state.logs),
        damage: assets.damage,
        expiry: assets.expiry,
        loans: assets.loans,
        services: assets.services,
        healthyItems: itemStates
            .where((status) => status == StockState.healthy)
            .length,
        totalItems: itemStates.length,
      ),
    );
  }
}

List<_UsageSummary> _topUsage(
  InventoryState state,
  List<ConsumptionLog> logs,
  ItemKind kind,
) {
  final totals = <String, double>{};
  final relevantAction = kind == ItemKind.chemical
      ? InventoryAction.consume
      : InventoryAction.breakage;
  for (final log in logs.where((value) => value.action == relevantAction)) {
    totals.update(
      log.itemId,
      (value) => value + log.amount,
      ifAbsent: () => log.amount,
    );
  }
  final summaries = totals.entries.map((entry) {
    if (kind == ItemKind.chemical) {
      final item = state.chemicals
          .where((value) => value.id == entry.key)
          .firstOrNull;
      return _UsageSummary(
        name: item?.name ?? 'Removed chemical',
        amount: entry.value,
        unit: item?.unit ?? '',
      );
    }
    final item = state.apparatus
        .where((value) => value.id == entry.key)
        .firstOrNull;
    return _UsageSummary(
      name: item?.name ?? 'Removed apparatus',
      amount: entry.value,
      unit: 'pcs',
    );
  }).toList()..sort((a, b) => b.amount.compareTo(a.amount));
  return summaries;
}

class _UsageSummary {
  const _UsageSummary({
    required this.name,
    required this.amount,
    required this.unit,
  });

  final String name;
  final double amount;
  final String unit;
}

class _TopUsageRow extends StatelessWidget {
  const _TopUsageRow({required this.rank, required this.summary});

  final int rank;
  final _UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank.',
              style: TextStyle(
                color: context.marginRedColor,
                fontFamily: 'Caveat',
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              summary.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatQuantity(summary.amount)} ${summary.unit}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.action,
    required this.trend,
    required this.color,
    super.key,
  });

  final String label;
  final InventoryAction action;
  final TrendComparison trend;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final totals = trend.current.of(action);
    final change = trend.countChange(action);
    final quantities = totals.quantityLabel;
    final muted = context.mutedInkColor;
    final IconData? arrow = change == null || change == 0
        ? null
        : change > 0
        ? Icons.arrow_upward
        : Icons.arrow_downward;
    return Semantics(
      label:
          '$label: ${totals.count}'
          '${quantities.isEmpty ? '' : ', $quantities'}, '
          '${trend.describe(action)}',
      child: NotebookCard(
        accent: color,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedQuantity(
              totals.count.toDouble(),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(label, style: TextStyle(color: muted, fontSize: 12)),
            if (quantities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  quantities,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (arrow != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        arrow,
                        size: 12,
                        // More restocking is good news; more usage or
                        // damage is flagged.
                        color:
                            (change! > 0) == (action == InventoryAction.restock)
                            ? context.healthyColor
                            : context.marginRedColor,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      change == null
                          ? trend.previous.of(action).count == 0 &&
                                    totals.count == 0
                                ? 'none in either period'
                                : 'none before'
                          : '${formatChange(change)} vs before',
                      maxLines: 2,
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunOutSection extends StatefulWidget {
  const _RunOutSection({required this.report});

  final RunOutReport report;

  @override
  State<_RunOutSection> createState() => _RunOutSectionState();
}

class _RunOutSectionState extends State<_RunOutSection> {
  static const _collapsedCount = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final muted = context.mutedInkColor;
    final shown = _expanded
        ? report.estimates
        : report.estimates.take(_collapsedCount).toList();
    return NotebookCard(
      tape: NotebookTape.pink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.estimates.isEmpty)
            Text(
              'No estimates yet. Each one needs $runOutMinEntries+ uses '
              'spread over $runOutMinSpanDays+ days within the last '
              '$runOutLookbackDays days; keep logging and they appear here.',
              key: const Key('runout-empty'),
              style: TextStyle(color: muted),
            ),
          for (final estimate in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Semantics(
                label:
                    '${estimate.name} runs out in ${estimate.headline}. '
                    '${estimate.explanation}',
                child: Column(
                  key: Key('runout-${estimate.itemId}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            estimate.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          estimate.headline,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: estimate.urgent
                                ? context.marginRedColor
                                : estimate.soon
                                ? context.lowColor
                                : null,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      estimate.explanation,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          if (report.estimates.length > _collapsedCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('runout-toggle'),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? 'show fewer'
                      : 'show all ${report.estimates.length}',
                ),
              ),
            ),
          if (report.withoutEstimate > 0) ...[
            const SizedBox(height: 6),
            Text(
              report.gapSummary,
              key: const Key('runout-gaps'),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Assumes the pace of the last $runOutLookbackDays days continues; '
            'restocks raise the stock and move the date out.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

List<ReportPdfUsageRow> _computeUsageRows(
  InventoryState state,
  List<ConsumptionLog> logs,
  ItemKind kind,
) {
  final usageRows = <ReportPdfUsageRow>[];
  if (kind == ItemKind.chemical) {
    for (final chem in state.chemicals) {
      final itemLogs = logs.where((l) => l.itemId == chem.id).toList();
      final used = itemLogs
          .where(
            (l) =>
                l.action == InventoryAction.consume ||
                l.action == InventoryAction.breakage,
          )
          .fold<double>(0.0, (sum, l) => sum + l.amount);
      if (used <= 0) continue;
      final added = itemLogs
          .where((l) => l.action == InventoryAction.restock)
          .fold<double>(0.0, (sum, l) => sum + l.amount);
      final left = chem.quantity;
      final startStock = math.max(0.0, left + used - added);
      final pct = chem.initialQuantity > 0
          ? (left / chem.initialQuantity * 100)
          : (startStock > 0 ? (left / startStock * 100) : 100.0);
      usageRows.add(
        ReportPdfUsageRow(
          name: chem.name,
          formulaOrCategory: chem.formula,
          unit: chem.unit,
          startStock: startStock,
          used: used,
          added: added,
          left: left,
          pct: pct,
        ),
      );
    }
  } else {
    for (final app in state.apparatus) {
      final itemLogs = logs.where((l) => l.itemId == app.id).toList();
      final used = itemLogs
          .where(
            (l) =>
                l.action == InventoryAction.breakage ||
                l.action == InventoryAction.consume,
          )
          .fold<double>(0.0, (sum, l) => sum + l.amount);
      if (used <= 0) continue;
      final added = itemLogs
          .where((l) => l.action == InventoryAction.restock)
          .fold<double>(0.0, (sum, l) => sum + l.amount);
      final left = app.quantity.toDouble();
      final startStock = math.max(0.0, left + used - added);
      final pct = app.initialQuantity > 0
          ? (left / app.initialQuantity * 100)
          : (startStock > 0 ? (left / startStock * 100) : 100.0);
      usageRows.add(
        ReportPdfUsageRow(
          name: app.name,
          formulaOrCategory: app.category,
          unit: 'pcs',
          startStock: startStock,
          used: used,
          added: added,
          left: left,
          pct: pct,
        ),
      );
    }
  }
  usageRows.sort((a, b) {
    if (b.used != a.used) return b.used.compareTo(a.used);
    if (b.added != a.added) return b.added.compareTo(a.added);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return usageRows;
}

String _itemName(InventoryState state, ConsumptionLog log) =>
    _nameOfItem(state, log.itemType, log.itemId);

String _unitOf(InventoryState state, ConsumptionLog log) {
  if (log.itemType == ItemKind.apparatus) return 'pcs';
  return state.chemicals
          .where((item) => item.id == log.itemId)
          .map((item) => item.unit)
          .firstOrNull ??
      '';
}

String _nameOfItem(InventoryState state, ItemKind kind, String id) {
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
