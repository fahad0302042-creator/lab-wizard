import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';

/// Lists every change waiting on this device, why it is waiting, and lets the
/// user retry or discard it (SYNC-01).
class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryProvider);
    final controller = ref.read(inventoryProvider.notifier);
    final outbox = inventory.outbox;
    final failed = inventory.failedCount;
    final waiting = outbox.length - failed;
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
                const Expanded(child: PageHeading('sync center')),
              ],
            ),
            const SizedBox(height: 12),
            NotebookCard(
              tape: outbox.isEmpty ? NotebookTape.green : NotebookTape.yellow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        failed > 0
                            ? Icons.cloud_off_outlined
                            : outbox.isEmpty
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        color: failed > 0
                            ? context.marginRedColor
                            : outbox.isEmpty
                            ? context.healthyColor
                            : context.lowColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          outbox.isEmpty
                              ? 'everything is on the server'
                              : failed > 0
                              ? '$failed need${failed == 1 ? 's' : ''} attention'
                              : '$waiting waiting for a connection',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lastSyncText(inventory.lastSyncedAt),
                    key: const Key('sync-last-success'),
                    style: TextStyle(color: context.mutedInkColor),
                  ),
                  if (outbox.isNotEmpty)
                    Text(
                      '$waiting waiting · $failed failed',
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: inventory.refreshing
                            ? null
                            : controller.refresh,
                        icon: inventory.refreshing
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                      if (failed > 0)
                        OutlinedButton.icon(
                          key: const Key('sync-retry-all'),
                          onPressed: inventory.refreshing
                              ? null
                              : controller.retryAll,
                          icon: const Icon(Icons.replay),
                          label: const Text('Retry all'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (outbox.isEmpty)
              const EmptyNotebookState(
                icon: Icons.cloud_done_outlined,
                title: 'nothing waiting',
                message:
                    'Changes made while offline appear here until they reach '
                    'the server.',
              )
            else ...[
              const PageHeading('queued changes', fontSize: 27),
              for (final operation in outbox)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OperationCard(
                    operation: operation,
                    busy: inventory.refreshing,
                    onRetry: () => controller.retryOperation(operation.id),
                    onDiscard: () => _confirmDiscard(
                      context,
                      operation,
                      () => controller.discardOperation(operation.id),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Changes are sent in the order they were made. Connection '
                'problems retry automatically; any other error waits here '
                'until you retry or discard it.',
                style: TextStyle(color: context.mutedInkColor, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _lastSyncText(DateTime? syncedAt) {
    if (syncedAt == null) {
      return 'No successful sync on this device yet.';
    }
    return 'Last successful sync: ${relativeTime(syncedAt)} '
        '(${DateFormat('d MMM, HH:mm').format(syncedAt)}).';
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    PendingOperation operation,
    Future<void> Function() discard,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this change?'),
        content: Text(
          '"${operation.description}" will be removed from this device and '
          'will never reach the server. The offline copy is put back to the '
          'way it was, and the next sync shows the server\'s numbers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: LabColors.marginRed,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await discard();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change discarded on this device')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.operation,
    required this.busy,
    required this.onRetry,
    required this.onDiscard,
  });

  final PendingOperation operation;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final failed = operation.isFailed;
    final statusColor = failed ? context.marginRedColor : context.lowColor;
    final error = operation.lastError;
    final details = StringBuffer('queued ${relativeTime(operation.createdAt)}');
    if (operation.attempts > 0) {
      details.write(
        ' · ${operation.attempts} attempt${operation.attempts == 1 ? '' : 's'}',
      );
    }
    final lastAttempt = operation.lastAttemptAt;
    if (lastAttempt != null) {
      details.write(', last ${relativeTime(lastAttempt)}');
    }
    return NotebookCard(
      accent: statusColor,
      paperclip: failed,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconFor(operation), color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  operation.description,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    failed ? 'needs attention' : 'waiting',
                    style: TextStyle(
                      color: statusColor,
                      fontFamily: 'Caveat',
                      fontSize: 16,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            details.toString(),
            style: TextStyle(color: context.mutedInkColor, fontSize: 12),
          ),
          if (error != null && error.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              friendlyErrorMessage(error),
              style: TextStyle(color: context.marginRedColor, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('retry now'),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: busy ? null : onDiscard,
                style: TextButton.styleFrom(
                  foregroundColor: context.mutedInkColor,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('discard'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(PendingOperation operation) {
    switch (operation.type) {
      case 'add_chemical':
        return Icons.science_outlined;
      case 'add_apparatus':
        return Icons.precision_manufacturing_outlined;
      case 'update_item':
        return Icons.edit_outlined;
      case 'undo_action':
        return Icons.undo;
      case 'inventory_action':
        return switch (operation.payload['action']) {
          'restock' => Icons.add_circle_outline,
          'breakage' => Icons.report_problem_outlined,
          _ => Icons.remove_circle_outline,
        };
      default:
        return Icons.cloud_upload_outlined;
    }
  }
}
