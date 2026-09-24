import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/apparatus_history.dart';
import '../domain/models.dart';

/// Which part of the timeline is shown.
enum HistoryFilter {
  all('all'),
  stock('stock'),
  loans('loans'),
  service('service');

  const HistoryFilter(this.label);

  final String label;

  bool matches(ApparatusEventKind kind) => switch (this) {
    HistoryFilter.all => true,
    HistoryFilter.stock =>
      kind == ApparatusEventKind.consume ||
          kind == ApparatusEventKind.restock ||
          kind == ApparatusEventKind.breakage ||
          kind == ApparatusEventKind.undo,
    HistoryFilter.loans =>
      kind == ApparatusEventKind.checkout ||
          kind == ApparatusEventKind.returned,
    HistoryFilter.service =>
      kind == ApparatusEventKind.scheduled ||
          kind == ApparatusEventKind.completed,
  };
}

IconData historyIcon(ApparatusEventKind kind) => switch (kind) {
  ApparatusEventKind.consume => Icons.remove,
  ApparatusEventKind.restock => Icons.add,
  ApparatusEventKind.breakage => Icons.broken_image_outlined,
  ApparatusEventKind.undo => Icons.undo,
  ApparatusEventKind.checkout => Icons.outbox_outlined,
  ApparatusEventKind.returned => Icons.assignment_return_outlined,
  ApparatusEventKind.scheduled => Icons.event_outlined,
  ApparatusEventKind.completed => Icons.task_alt_outlined,
};

Color historyColor(BuildContext context, ApparatusEventKind kind) =>
    switch (kind) {
      ApparatusEventKind.breakage => context.marginRedColor,
      ApparatusEventKind.restock ||
      ApparatusEventKind.returned ||
      ApparatusEventKind.completed => context.healthyColor,
      ApparatusEventKind.checkout ||
      ApparatusEventKind.scheduled => context.lowColor,
      ApparatusEventKind.consume ||
      ApparatusEventKind.undo => context.mutedInkColor,
    };

/// Unified timeline of stock changes, loans and service tasks for one
/// apparatus, with a shareable plain-text report (GEAR-04).
class ApparatusHistoryScreen extends ConsumerStatefulWidget {
  const ApparatusHistoryScreen({super.key, required this.apparatusId});

  final String apparatusId;

  @override
  ConsumerState<ApparatusHistoryScreen> createState() =>
      _ApparatusHistoryScreenState();
}

class _ApparatusHistoryScreenState
    extends ConsumerState<ApparatusHistoryScreen> {
  HistoryFilter _filter = HistoryFilter.all;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final item = state.apparatus
        .where((entry) => entry.id == widget.apparatusId)
        .firstOrNull;
    final events = item == null
        ? const <ApparatusEvent>[]
        : buildApparatusHistory(
            apparatusId: item.id,
            logs: state.logs,
            reversals: state.reversals,
            checkouts: state.checkouts,
            services: state.services,
          );
    final visible = events
        .where((event) => _filter.matches(event.kind))
        .toList();
    final summary = item == null
        ? null
        : ApparatusHistorySummary.of(
            events,
            checkouts: state.checkouts,
            services: state.services,
            apparatusId: item.id,
          );
    final dateFormat = DateFormat('d MMM yyyy · HH:mm');
    return Scaffold(
      body: NotebookPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(notebookGutter, 20, 18, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: PageHeading(
                    item == null ? 'history' : '${item.name} history',
                    fontSize: 30,
                  ),
                ),
                IconButton(
                  key: const Key('history-share'),
                  tooltip: 'Share history',
                  onPressed: item == null || _sharing
                      ? null
                      : () => _share(item, events, summary!),
                  icon: _sharing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                ),
              ],
            ),
            if (item == null || summary == null)
              const EmptyNotebookState(
                icon: Icons.search_off,
                title: 'item not found',
                message: 'It may have been removed on another device.',
              )
            else ...[
              const SizedBox(height: 12),
              NotebookCard(
                key: const Key('history-summary'),
                tape: NotebookTape.yellow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatQuantity(item.quantity)} pcs in stock · '
                      '${formatQuantity(state.checkedOutCount(item.id))} out',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _SummaryLine(
                      icon: Icons.broken_image_outlined,
                      text:
                          '${summary.damaged} damage '
                          '${summary.damaged == 1 ? 'entry' : 'entries'}',
                    ),
                    _SummaryLine(
                      icon: Icons.outbox_outlined,
                      text:
                          '${summary.loans} ${summary.loans == 1 ? 'loan' : 'loans'}'
                          ' · ${summary.openLoans} open'
                          '${summary.lateReturns > 0 ? ' · ${summary.lateReturns} returned late' : ''}',
                    ),
                    _SummaryLine(
                      icon: Icons.build_outlined,
                      text:
                          '${summary.completedTasks} completed '
                          '${summary.completedTasks == 1 ? 'task' : 'tasks'}'
                          ' · ${summary.openTasks} open',
                    ),
                    if (summary.lastCalibration != null)
                      _SummaryLine(
                        icon: Icons.straighten_outlined,
                        text:
                            'last calibration '
                            '${DateFormat('d MMM yyyy').format(summary.lastCalibration!)}',
                      ),
                    if (summary.lastMaintenance != null)
                      _SummaryLine(
                        icon: Icons.handyman_outlined,
                        text:
                            'last maintenance '
                            '${DateFormat('d MMM yyyy').format(summary.lastMaintenance!)}',
                      ),
                    if (summary.nextDue != null)
                      _SummaryLine(
                        icon: Icons.event_outlined,
                        text:
                            'next due '
                            '${DateFormat('d MMM yyyy').format(summary.nextDue!)}',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in HistoryFilter.values)
                    ChoiceChip(
                      key: Key('history-filter-${filter.name}'),
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    events.isEmpty
                        ? 'No activity yet. Uses, damage, loans and service '
                              'tasks will show up here.'
                        : 'Nothing of this kind yet.',
                    key: const Key('history-empty'),
                    style: TextStyle(color: context.mutedInkColor),
                  ),
                )
              else
                for (final event in visible)
                  ListTile(
                    key: Key('timeline-${event.key}'),
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: historyColor(
                        context,
                        event.kind,
                      ).withValues(alpha: .15),
                      child: Icon(
                        historyIcon(event.kind),
                        color: historyColor(context, event.kind),
                      ),
                    ),
                    title: Text(event.title),
                    subtitle: Text(
                      '${dateFormat.format(event.time)}'
                      '${event.detail.isEmpty ? '' : ' · ${event.detail}'}',
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _share(
    Apparatus item,
    List<ApparatusEvent> events,
    ApparatusHistorySummary summary,
  ) async {
    setState(() => _sharing = true);
    final report = buildApparatusHistoryReport(
      item: item,
      events: events,
      summary: summary,
    );
    try {
      final directory = await getTemporaryDirectory();
      final safeName = item.name
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .toLowerCase();
      final file = File('${directory.path}/lab-wizard-$safeName-history.txt');
      await file.writeAsString(report, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: '${item.name} history',
          text: '${item.name} history',
          files: [XFile(file.path, mimeType: 'text/plain')],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.mutedInkColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.mutedInkColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
