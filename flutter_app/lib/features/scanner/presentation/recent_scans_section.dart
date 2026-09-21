import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../domain/recent_scan.dart';
import '../scanner_providers.dart';

/// The scanner's history (SCAN-01): the last codes read on this device for
/// the signed-in user, newest first, with one tap back into the item.
class RecentScansSection extends ConsumerStatefulWidget {
  const RecentScansSection({this.collapsedCount = 5, super.key});

  /// How many entries are shown before the *show all* toggle.
  final int collapsedCount;

  @override
  ConsumerState<RecentScansSection> createState() => _RecentScansSectionState();
}

class _RecentScansSectionState extends ConsumerState<RecentScansSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(recentScansProvider);
    if (scans.isEmpty) return const SizedBox.shrink();
    final inventory = ref.watch(inventoryProvider);
    final visible = _expanded ? scans : scans.take(widget.collapsedCount);
    final hidden = scans.length - widget.collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          'recent scans',
          trailing: TextButton.icon(
            key: const Key('recent-scans-clear'),
            onPressed: () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('clear'),
          ),
        ),
        Text(
          'Kept on this device only, for your account.',
          style: TextStyle(color: context.mutedInkColor, fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final scan in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecentScanTile(
              scan: scan,
              exists: _exists(inventory, scan),
              onTap: () => _open(context, inventory, scan),
            ),
          ),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('recent-scans-toggle'),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'show fewer' : 'show all ${scans.length}',
              ),
            ),
          ),
      ],
    );
  }

  static bool _exists(InventoryState inventory, RecentScan scan) {
    if (!scan.found) return false;
    return switch (scan.kind!) {
      ItemKind.chemical => inventory.chemicals.any(
        (item) => item.id == scan.itemId,
      ),
      ItemKind.apparatus => inventory.apparatus.any(
        (item) => item.id == scan.itemId,
      ),
    };
  }

  Future<void> _open(
    BuildContext context,
    InventoryState inventory,
    RecentScan scan,
  ) async {
    if (!scan.found) {
      await _showUnknownCode(context, scan);
      return;
    }
    if (!_exists(inventory, scan)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${scan.name} is no longer in your notebook.')),
      );
      return;
    }
    await showItemDetailSheet(context, ref, scan.kind!, scan.itemId!);
  }

  Future<void> _showUnknownCode(BuildContext context, RecentScan scan) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Code not in your notebook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scanned ${relativeTime(scan.scannedAt)}. Lab Wizard labels '
              'start with "labwizard:"; other codes are not matched to items.',
              style: TextStyle(color: context.mutedInkColor, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SelectableText(
              scan.raw,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: scan.raw));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear recent scans?'),
        content: const Text(
          'The history is only kept on this device; items and their '
          'stock are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('recent-scans-clear-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(recentScansProvider.notifier).clear();
    }
  }
}

class _RecentScanTile extends StatelessWidget {
  const _RecentScanTile({
    required this.scan,
    required this.exists,
    required this.onTap,
  });

  final RecentScan scan;
  final bool exists;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    final when = relativeTime(scan.scannedAt);
    final title = scan.found ? scan.name : 'Unknown code';
    final detail = scan.found
        ? [if (scan.subtitle.isNotEmpty) scan.subtitle, when].join(' · ')
        : '${_shorten(scan.raw)} · $when';
    final icon = !scan.found
        ? Icons.help_outline
        : scan.kind == ItemKind.chemical
        ? Icons.science_outlined
        : Icons.precision_manufacturing_outlined;

    return Semantics(
      button: true,
      label: scan.found
          ? '$title, ${scan.kind!.name}, scanned $when'
          : 'Unknown code scanned $when',
      child: NotebookCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: scan.found && exists ? null : muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'ArchitectsDaughter',
                      fontWeight: FontWeight.w700,
                      color: scan.found && exists ? null : muted,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (scan.found && !exists)
              Text('removed', style: TextStyle(color: muted, fontSize: 12))
            else if (!scan.found)
              Text('not matched', style: TextStyle(color: muted, fontSize: 12))
            else
              const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  static String _shorten(String raw) {
    final flat = raw.replaceAll(RegExp(r'\s+'), ' ');
    return flat.length <= 32 ? flat : '${flat.substring(0, 31)}…';
  }
}
