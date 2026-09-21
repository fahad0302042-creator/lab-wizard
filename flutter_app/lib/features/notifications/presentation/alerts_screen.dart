import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../../sync/presentation/sync_center_screen.dart';
import '../notification_providers.dart';

/// Everything that needs attention, in one list (NOTIFY-02/03/04). The same
/// alerts drive the system notifications, so what you see here is what the
/// phone would have told you about.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final inventory = ref.watch(inventoryProvider);
    final urgent = alerts.where((alert) => alert.kind.urgent).toList();
    final soon = alerts.where((alert) => !alert.kind.urgent).toList();
    final summary = weeklySummaryText(
      alerts: alerts,
      logs: inventory.logs,
      chemicalCount: inventory.chemicals.length,
      apparatusCount: inventory.apparatus.length,
    );
    return Scaffold(
      body: NotebookPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(54, 12, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                const Expanded(child: PageHeading('needs attention')),
              ],
            ),
            const SizedBox(height: 8),
            if (alerts.isEmpty)
              const EmptyNotebookState(
                icon: Icons.notifications_off_outlined,
                title: 'All quiet',
                message:
                    'Nothing is low, expired, overdue or waiting to sync. '
                    'Reminders will appear here as due dates approach.',
              ),
            if (urgent.isNotEmpty) ...[
              _SectionLabel('now · ${urgent.length}'),
              for (final alert in urgent) _AlertTile(alert: alert),
              const SizedBox(height: 12),
            ],
            if (soon.isNotEmpty) ...[
              _SectionLabel('coming up · ${soon.length}'),
              for (final alert in soon) _AlertTile(alert: alert),
              const SizedBox(height: 12),
            ],
            NotebookCard(
              key: const Key('weekly-summary-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_view_week_outlined,
                        color: LabColors.marginRed,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'this week',
                        style: TextStyle(
                          fontFamily: 'Kalam',
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(summary, style: const TextStyle(height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Kalam',
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: context.mutedInkColor,
        ),
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final AppAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = alert.kind.urgent ? LabColors.marginRed : LabColors.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NotebookCard(
        key: Key('alert-${alert.id}'),
        accent: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () {
          final kind = alert.itemKind;
          final id = alert.itemId;
          if (kind != null && id != null) {
            showItemDetailSheet(context, ref, kind, id);
          } else if (alert.kind == AlertKind.syncFailed) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SyncCenterScreen()),
            );
          }
        },
        child: Row(
          children: [
            Icon(_iconFor(alert.kind), color: color, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.body,
                    style: TextStyle(
                      color: context.mutedInkColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert.kind.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      letterSpacing: .4,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(AlertKind kind) => switch (kind) {
    AlertKind.empty => Icons.inventory_2_outlined,
    AlertKind.lowStock => Icons.trending_down,
    AlertKind.expired || AlertKind.expiringSoon => Icons.event_busy_outlined,
    AlertKind.overdueReturn => Icons.assignment_return_outlined,
    AlertKind.serviceDue || AlertKind.serviceOverdue => Icons.build_outlined,
    AlertKind.syncFailed => Icons.cloud_off_outlined,
  };
}

/// Dashboard entry point: a small card that summarises non-stock alerts
/// (stock already has its own attention card) and opens [AlertsScreen].
class RemindersCard extends ConsumerWidget {
  const RemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref
        .watch(alertsProvider)
        .where((alert) => alert.kind.channel != AlertChannel.stock)
        .toList();
    if (alerts.isEmpty) return const SizedBox.shrink();
    final urgent = alerts.where((alert) => alert.kind.urgent).length;
    final parts = <String>[
      for (final kind in AlertKind.values)
        if (alerts.any((alert) => alert.kind == kind))
          '${alerts.where((alert) => alert.kind == kind).length} ${kind.label}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: NotebookCard(
        key: const Key('reminders-card'),
        accent: urgent > 0 ? LabColors.marginRed : LabColors.amber,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
        ),
        child: Row(
          children: [
            Icon(
              Icons.alarm_on_outlined,
              color: urgent > 0 ? LabColors.marginRed : LabColors.amber,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alerts.length} reminder${alerts.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(parts.join(' · ')),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
