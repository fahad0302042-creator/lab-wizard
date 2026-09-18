import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    required this.user,
    required this.onNavigate,
    required this.onSettings,
    super.key,
  });

  final User user;
  final ValueChanged<int> onNavigate;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryProvider);
    final firstName = _firstName(user);
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final weeklyLogs = inventory.logs
        .where((log) => !log.loggedAt.isBefore(weekStart))
        .toList();

    return RefreshIndicator(
      onRefresh: ref.read(inventoryProvider.notifier).refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(42, 18, 18, 32),
        children: [
          StaggerIn(
            index: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d').format(now),
                        style: TextStyle(color: context.mutedInkColor),
                      ),
                      const SizedBox(height: 3),
                      PageHeading('${_greeting(now)}, $firstName'),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Settings',
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
          if (inventory.error != null || inventory.pendingCount > 0) ...[
            const SizedBox(height: 8),
            _SyncBanner(state: inventory),
          ],
          const SizedBox(height: 14),
          TextField(
            readOnly: true,
            onTap: () => onNavigate(1),
            decoration: const InputDecoration(
              hintText: 'Search chemicals or apparatus…',
              prefixIcon: Icon(Icons.search),
              suffixIcon: Icon(Icons.arrow_forward),
            ),
          ),
          const SizedBox(height: 18),
          if (inventory.attentionCount > 0) ...[
            StaggerIn(
              index: 1,
              child: NotebookCard(
                accent: LabColors.marginRed,
                onTap: () => onNavigate(1),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notification_important_outlined,
                      color: LabColors.marginRed,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${inventory.attentionCount} ${inventory.attentionCount == 1 ? 'item needs' : 'items need'} attention',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text('Low and empty stock should be checked.'),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.45,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricCard(
                index: 2,
                icon: Icons.science_outlined,
                value: inventory.chemicals.length.toDouble(),
                label: 'chemicals',
                color: LabColors.blue,
              ),
              _MetricCard(
                index: 3,
                icon: Icons.precision_manufacturing_outlined,
                value: inventory.apparatus.length.toDouble(),
                label: 'apparatus',
                color: LabColors.green,
              ),
              _MetricCard(
                index: 4,
                icon: Icons.warning_amber_rounded,
                value: inventory.attentionCount.toDouble(),
                label: 'need attention',
                color: LabColors.marginRed,
              ),
              _MetricCard(
                index: 5,
                icon: Icons.history,
                value: weeklyLogs.length.toDouble(),
                label: 'actions this week',
                color: LabColors.amber,
              ),
            ],
          ),
          const SizedBox(height: 26),
          const PageHeading('quick actions', trailing: SizedBox.shrink()),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => onNavigate(2),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    showAddItemSheet(context, ref, ItemKind.chemical),
                icon: const Icon(Icons.add),
                label: const Text('Chemical'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    showAddItemSheet(context, ref, ItemKind.apparatus),
                icon: const Icon(Icons.add),
                label: const Text('Apparatus'),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const PageHeading('7-day activity'),
          NotebookCard(child: _WeekActivity(logs: weeklyLogs)),
          const SizedBox(height: 26),
          const PageHeading('recent activity'),
          if (inventory.logs.isEmpty)
            const EmptyNotebookState(
              icon: Icons.edit_note,
              title: 'nothing logged yet',
              message: 'Consume, restock, or record a breakage and it will appear here.',
            )
          else
            ...inventory.logs.take(6).toList().asMap().entries.map((entry) {
              final log = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: StaggerIn(
                  index: entry.key,
                  child: _ActivityRow(log: log, inventory: inventory),
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _firstName(User user) {
    final metadataName = user.userMetadata?['name']?.toString().trim();
    final fallback = user.email?.split('@').first ?? 'friend';
    return (metadataName == null || metadataName.isEmpty
            ? fallback
            : metadataName)
        .split(RegExp(r'\s+'))
        .first;
  }

  static String _greeting(DateTime now) => switch (now.hour) {
    < 12 => 'good morning',
    < 17 => 'good afternoon',
    < 21 => 'good evening',
    _ => 'working late',
  };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.index,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final int index;
  final IconData icon;
  final double value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StaggerIn(
      index: index,
      child: NotebookCard(
        accent: color,
        rotation: index.isEven ? -.006 : .006,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 21),
            AnimatedQuantity(
              value,
              style: const TextStyle(
                fontSize: 28,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.mutedInkColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.state});

  final InventoryState state;

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingCount > 0;
    return Material(
      color: (pending ? LabColors.amber : LabColors.blue).withValues(
        alpha: .12,
      ),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(
              pending ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pending
                    ? '${state.pendingCount} change${state.pendingCount == 1 ? '' : 's'} waiting to sync'
                    : state.error!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekActivity extends StatelessWidget {
  const _WeekActivity({required this.logs});

  final List<ConsumptionLog> logs;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(
      7,
      (index) => DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 6 - index)),
    );
    final counts = days
        .map(
          (day) => logs
              .where((log) => localDayKey(log.loggedAt) == localDayKey(day))
              .length,
        )
        .toList();
    final maxCount = counts.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          final ratio = counts[index] / maxCount;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  counts[index] == 0 ? '' : '${counts[index]}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: ratio),
                  duration: Duration(milliseconds: 400 + index * 55),
                  curve: Curves.easeOutBack,
                  builder: (_, value, _) => Container(
                    height: 68 * value + 5,
                    width: 13,
                    decoration: BoxDecoration(
                      color: LabColors.marginRed.withValues(alpha: .78),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  DateFormat.E().format(days[index]).substring(0, 1),
                  style: TextStyle(color: context.mutedInkColor, fontSize: 12),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.log, required this.inventory});

  final ConsumptionLog log;
  final InventoryState inventory;

  @override
  Widget build(BuildContext context) {
    final name = log.itemType == ItemKind.chemical
        ? inventory.chemicals
              .where((item) => item.id == log.itemId)
              .map((item) => item.name)
              .firstOrNull
        : inventory.apparatus
              .where((item) => item.id == log.itemId)
              .map((item) => item.name)
              .firstOrNull;
    final actionColor = switch (log.action) {
      InventoryAction.restock => LabColors.green,
      InventoryAction.consume => LabColors.amber,
      InventoryAction.breakage => LabColors.marginRed,
    };
    return NotebookCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: actionColor.withValues(alpha: .12),
            foregroundColor: actionColor,
            child: Icon(switch (log.action) {
              InventoryAction.restock => Icons.add,
              InventoryAction.consume => Icons.remove,
              InventoryAction.breakage => Icons.broken_image_outlined,
            }, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Removed item',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${log.action.name} · ${DateFormat.MMMd().format(log.loggedAt.toLocal())}',
                  style: TextStyle(color: context.mutedInkColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            formatQuantity(log.amount),
            style: TextStyle(
              color: actionColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
