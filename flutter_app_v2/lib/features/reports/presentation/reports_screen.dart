import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/models.dart';

/// What happened this month: usage per reagent, a daily bar, and a PDF you can
/// hand to whoever orders the stock.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _exporting = false;

  bool _inMonth(DateTime value) {
    final local = value.toLocal();
    return local.year == _month.year && local.month == _month.month;
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final logs = state.logs.where((log) => _inMonth(log.loggedAt)).toList();

    final used = logs
        .where(
          (log) =>
              log.action == InventoryAction.consume ||
              log.action == InventoryAction.breakage,
        )
        .toList();
    final added = logs
        .where((log) => log.action == InventoryAction.restock)
        .toList();

    // Sum per item so the list answers "what do I actually use up".
    final totals = <String, double>{};
    final kinds = <String, ItemKind>{};
    for (final log in used) {
      totals.update(
        log.itemId,
        (value) => value + log.amount,
        ifAbsent: () => log.amount,
      );
      kinds[log.itemId] = log.itemType;
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String nameOf(String id) {
      final chemical = state.chemicals
          .where((value) => value.id == id)
          .firstOrNull;
      if (chemical != null) return chemical.name;
      final apparatus = state.apparatus
          .where((value) => value.id == id)
          .firstOrNull;
      return apparatus?.name ?? 'Removed item';
    }

    String unitOf(String id) {
      final chemical = state.chemicals
          .where((value) => value.id == id)
          .firstOrNull;
      return chemical?.unit ?? 'pcs';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      children: [
        Text('Reports', style: context.aside),
        const SizedBox(height: 4),
        Text(
          DateFormat('MMMM yyyy').format(_month),
          style: TextStyle(
            fontSize: 27,
            height: 1.05,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w600,
            color: lab.ink,
          ),
        ),
        const SizedBox(height: 14),
        Row(
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
                '${used.length} used · ${added.length} restocked',
                textAlign: TextAlign.center,
                style: context.label,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Divider(color: lab.hair, height: 1),
        const SizedBox(height: 16),
        _DailyBars(logs: logs, month: _month),
        const SizedBox(height: 22),
        Text('MOST USED', style: context.label),
        const SizedBox(height: 10),
        if (ranked.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nothing logged this month.',
              style: context.aside.copyWith(fontSize: 16),
            ),
          )
        else
          ...ranked.take(12).map((entry) {
            final max = ranked.first.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nameOf(entry.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.itemName,
                        ),
                      ),
                      Text(
                        '${formatQuantity(entry.value)} ${unitOf(entry.key)}',
                        style: context.figure.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : entry.value / max,
                      minHeight: 4,
                      backgroundColor: lab.hair,
                      valueColor: AlwaysStoppedAnimation(lab.sage),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _exporting || logs.isEmpty
              ? null
              : () => _export(state, logs, nameOf, unitOf),
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(_exporting ? 'Preparing…' : 'Share PDF report'),
        ),
      ],
    );
  }

  Future<void> _export(
    InventoryState state,
    List<ConsumptionLog> logs,
    String Function(String) nameOf,
    String Function(String) unitOf,
  ) async {
    setState(() => _exporting = true);
    try {
      final theme = pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
      final document = pw.Document(
        title: 'Lab Wizard ${DateFormat('MMMM yyyy').format(_month)}',
        theme: theme,
      );
      final used = logs
          .where((log) => log.action != InventoryAction.restock)
          .toList()
        ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
          build: (_) => [
            pw.Text(
              'Lab Wizard — ${DateFormat('MMMM yyyy').format(_month)}',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${state.chemicals.length} reagents · '
              '${state.apparatus.length} apparatus · '
              '${logs.length} entries this month',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Item', 'Action', 'Amount', 'Note'],
              data: used
                  .map(
                    (log) => [
                      DateFormat('d MMM').format(log.loggedAt.toLocal()),
                      nameOf(log.itemId),
                      log.action.name,
                      '${formatQuantity(log.amount)} ${unitOf(log.itemId)}',
                      log.note,
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              border: null,
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        name: 'lab-wizard-${DateFormat('yyyy-MM').format(_month)}.pdf',
        onLayout: (_) => document.save(),
      );
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// One bar per day of the month. Quiet by design: it shows shape, not detail.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.logs, required this.month});

  final List<ConsumptionLog> logs;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final counts = List<int>.filled(days, 0);
    for (final log in logs) {
      final day = log.loggedAt.toLocal().day;
      if (day >= 1 && day <= days) counts[day - 1]++;
    }
    final maxCount = math.max(1, counts.reduce(math.max));

    return SizedBox(
      height: 78,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(days, (index) {
          final ratio = counts[index] / maxCount;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: math.max(2, ratio * 62),
                    decoration: BoxDecoration(
                      color: counts[index] == 0
                          ? lab.hair
                          : lab.sage.withValues(alpha: .75),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
