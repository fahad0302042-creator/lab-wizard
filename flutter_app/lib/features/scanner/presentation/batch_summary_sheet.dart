import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../domain/scan_batch.dart';

/// Shows what a batch scan collected (SCAN-02). Resolves to `true` when the
/// batch is finished and should be cleared, `false` to keep scanning into it.
Future<bool> showBatchSummarySheet(
  BuildContext context,
  ScanBatch batch,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NotebookSheetFrame(child: BatchSummary(batch: batch)),
  );
  return result ?? false;
}

class BatchSummary extends ConsumerWidget {
  const BatchSummary({required this.batch, super.key});

  final ScanBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.mutedInkColor;
    final unknown = batch.unknown.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SketchTitle('batch scan', fontSize: 30),
        Text(batch.summaryLine, style: TextStyle(color: muted)),
        if (batch.duplicateCount > 0)
          Text(
            '${batch.duplicateCount} repeated read'
            '${batch.duplicateCount == 1 ? '' : 's'} counted, not listed twice.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        const SizedBox(height: 14),
        for (final entry in batch.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NotebookCard(
              key: Key(
                'batch-entry-${entry.match.kind.name}-${entry.match.id}',
              ),
              onTap: () => showItemDetailSheet(
                context,
                ref,
                entry.match.kind,
                entry.match.id,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    entry.match.kind == ItemKind.chemical
                        ? Icons.science_outlined
                        : Icons.precision_manufacturing_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.match.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (entry.match.subtitle.isNotEmpty)
                          Text(
                            entry.match.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (entry.count > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '×${entry.count}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        if (unknown.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Not in your notebook',
            style: TextStyle(color: muted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final code in unknown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: muted, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      code.key,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (code.value > 1)
                    Text('×${code.value}', style: TextStyle(color: muted)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('batch-keep-scanning'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep scanning'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('batch-done'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
