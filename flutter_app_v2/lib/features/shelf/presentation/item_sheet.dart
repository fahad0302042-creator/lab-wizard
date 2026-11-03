import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_jar.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import 'action_sheet.dart';
import 'edit_item_sheet.dart';
import 'log_sheet.dart';

/// The item page, opened from a row, a scan, or a search result.
Future<void> showItemSheet(
  BuildContext context, {
  required String itemId,
  required ItemKind kind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.lab.bone,
    builder: (_) => _ItemSheet(itemId: itemId, kind: kind),
  );
}

class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.itemId, required this.kind});

  final String itemId;
  final ItemKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final views = kind == ItemKind.chemical
        ? state.chemicals.map(ItemView.fromChemical).toList()
        : state.apparatus.map(ItemView.fromApparatus).toList();
    final match = views.where((item) => item.id == itemId);
    if (match.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('This item was removed.', style: context.aside),
      );
    }
    final item = match.first;
    final metrics = item.metrics;
    final logs = state.logs.where((log) => log.itemId == itemId).take(10);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .74,
      minChildSize: .44,
      maxChildSize: .95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: lab.hair,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.06,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w600,
                        color: lab.ink,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item.subtitle,
                        style: context.formula.copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              GlassJar(metrics: metrics, width: 46, height: 58),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatQuantity(item.quantity),
                style: TextStyle(
                  fontSize: 40,
                  height: .95,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w600,
                  color: lab.ink,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  item.unit,
                  style: context.label.copyWith(fontSize: 11),
                ),
              ),
              const Spacer(),
              JarTicks(
                count: metrics.ticks,
                color: lab.forState(metrics.signal),
                width: 18,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _OrderLevelRow(item: item),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _log(
                    context,
                    ref,
                    item,
                    item.isChemical
                        ? InventoryAction.consume
                        : InventoryAction.breakage,
                  ),
                  child: Text(item.isChemical ? 'Log use' : 'Log breakage'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _log(context, ref, item, InventoryAction.restock),
                  child: const Text('Restock'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('HISTORY', style: context.label),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Nothing logged yet. Swipe a row to log use.',
                style: context.aside.copyWith(fontSize: 16),
              ),
            )
          else
            ...logs.map(
              (log) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showLogSheet(
                  context,
                  log: log,
                  itemName: item.name,
                  unit: item.unit,
                ),
                child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 7,
                  horizontal: 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (log.action) {
                        InventoryAction.restock => Icons.add,
                        InventoryAction.consume => Icons.remove,
                        InventoryAction.breakage => Icons.close,
                      },
                      size: 14,
                      color: lab.soft,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.note.isEmpty ? log.action.name : log.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: lab.ink),
                      ),
                    ),
                    Text(
                      DateFormat('d MMM').format(log.loggedAt.toLocal()),
                      style: context.aside.copyWith(fontSize: 15),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      child: Text(
                        formatQuantity(log.amount),
                        textAlign: TextAlign.right,
                        style: context.figure.copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('NOTES', style: context.label),
            const SizedBox(height: 6),
            Text(
              item.notes,
              style: TextStyle(fontSize: 13, height: 1.5, color: lab.soft),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showEditItemSheet(context, item: item),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Edit item'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _delete(context, ref, item),
                  icon: Icon(Icons.delete_outline, size: 17, color: lab.berry),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: lab.berry),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _log(
    BuildContext context,
    WidgetRef ref,
    ItemView item,
    InventoryAction action,
  ) async {
    final log = await showActionSheet(context, ref, item: item, action: action);
    if (log != null && context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ItemView item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text(
          '${item.name} and everything logged against it will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(inventoryProvider.notifier).deleteItem(item.kind, item.id);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }
}

/// The manual low-stock switch.
///
/// Nothing is flagged until a level exists, so this row is the one place that
/// decides whether an item can ever ask for attention. It sits directly under
/// the quantity, because that is where the question "when should this shout at
/// me?" actually occurs to someone.
class _OrderLevelRow extends ConsumerWidget {
  const _OrderLevelRow({required this.item});

  final ItemView item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final hasLevel = item.threshold > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showOrderLevelSheet(context, item: item),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasLevel ? lab.hair : lab.clay),
          color: hasLevel
              ? Colors.transparent
              : lab.clay.withValues(alpha: .06),
        ),
        child: Row(
          children: [
            Icon(
              hasLevel ? Icons.notifications_none : Icons.notifications_off,
              size: 16,
              color: hasLevel ? lab.soft : lab.clay,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasLevel
                        ? 'Order level: ${formatQuantity(item.threshold)} '
                              '${item.unit}'
                        : 'No order level set',
                    style: context.itemName.copyWith(fontSize: 13.5),
                  ),
                  Text(
                    hasLevel
                        ? 'This shelf asks for attention below that.'
                        : 'Set one to let this shelf warn you.',
                    style: context.aside.copyWith(
                      fontSize: 14,
                      color: hasLevel ? lab.soft : lab.clay,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              hasLevel ? 'Change' : 'Set',
              style: context.label.copyWith(
                fontSize: LabType.micro,
                letterSpacing: 1,
                color: hasLevel ? lab.soft : lab.clay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
