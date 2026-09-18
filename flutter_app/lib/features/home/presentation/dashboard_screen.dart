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
        padding: const EdgeInsets.fromLTRB(54, 18, 20, 32),
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
                IconButton(
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
            onTap: () => _showGlobalSearch(context, ref),
            decoration: const InputDecoration(
              hintText: 'search chemicals, apparatus…',
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
                onTap: () => _showAttentionSheet(context, ref),
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
                onTap: () => onNavigate(1),
              ),
              _MetricCard(
                index: 3,
                icon: Icons.precision_manufacturing_outlined,
                value: inventory.apparatus.length.toDouble(),
                label: 'apparatus',
                color: LabColors.green,
                onTap: () => onNavigate(3),
              ),
              _MetricCard(
                index: 4,
                icon: Icons.warning_amber_rounded,
                value: inventory.attentionCount.toDouble(),
                label: 'need attention',
                color: LabColors.marginRed,
                onTap: () => _showAttentionSheet(context, ref),
              ),
              _MetricCard(
                index: 5,
                icon: Icons.history,
                value: weeklyLogs.length.toDouble(),
                label: 'actions this week',
                color: LabColors.amber,
                onTap: () => onNavigate(4),
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

  void _showGlobalSearch(BuildContext context, WidgetRef ref) {
    final inventory = ref.read(inventoryProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .86,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: sheetContext.paperColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: _GlobalSearchSheet(
              inventory: inventory,
              onOpen: (kind, id) {
                Navigator.pop(sheetContext);
                Future<void>.delayed(const Duration(milliseconds: 120), () {
                  if (context.mounted) {
                    showItemDetailSheet(context, ref, kind, id);
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showAttentionSheet(BuildContext context, WidgetRef ref) {
    final inventory = ref.read(inventoryProvider);
    final results = [
      ...inventory.chemicals
          .where((item) => item.stockState != StockState.healthy)
          .map(
            (item) => _GlobalResult(
              kind: ItemKind.chemical,
              id: item.id,
              name: item.name,
              subtitle: item.formula,
              quantity: item.quantity,
              unit: item.unit,
              status: item.stockState,
            ),
          ),
      ...inventory.apparatus
          .where((item) => item.stockState != StockState.healthy)
          .map(
            (item) => _GlobalResult(
              kind: ItemKind.apparatus,
              id: item.id,
              name: item.name,
              subtitle: item.category,
              quantity: item.quantity,
              unit: 'pcs',
              status: item.stockState,
            ),
          ),
    ]..sort((a, b) => a.quantity.compareTo(b.quantity));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .78,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sheetContext.paperColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: _ResultList(
            title: 'needs attention',
            results: results,
            emptyMessage: 'Everything is currently above its low-stock level.',
            onOpen: (kind, id) {
              Navigator.pop(sheetContext);
              Future<void>.delayed(const Duration(milliseconds: 120), () {
                if (context.mounted) {
                  showItemDetailSheet(context, ref, kind, id);
                }
              });
            },
          ),
        ),
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

class _GlobalSearchSheet extends StatefulWidget {
  const _GlobalSearchSheet({required this.inventory, required this.onOpen});

  final InventoryState inventory;
  final void Function(ItemKind kind, String id) onOpen;

  @override
  State<_GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<_GlobalSearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final results = query.isEmpty
        ? const <_GlobalResult>[]
        : [
                ...widget.inventory.chemicals.map(
                  (item) => _GlobalResult(
                    kind: ItemKind.chemical,
                    id: item.id,
                    name: item.name,
                    subtitle: item.formula,
                    quantity: item.quantity,
                    unit: item.unit,
                    status: item.stockState,
                    searchText: item.notes,
                  ),
                ),
                ...widget.inventory.apparatus.map(
                  (item) => _GlobalResult(
                    kind: ItemKind.apparatus,
                    id: item.id,
                    name: item.name,
                    subtitle: item.category,
                    quantity: item.quantity,
                    unit: 'pcs',
                    status: item.stockState,
                    searchText: item.notes,
                  ),
                ),
              ]
              .where(
                (item) => '${item.name} ${item.subtitle} ${item.searchText}'
                    .toLowerCase()
                    .contains(query),
              )
              .take(40)
              .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
          child: Column(
            children: [
              const PageHeading('search the notebook'),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'name, formula, or category…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: query.isEmpty
              ? const EmptyNotebookState(
                  icon: Icons.manage_search,
                  title: 'find anything quickly',
                  message: 'Search chemicals and apparatus together.',
                )
              : _ResultList(
                  results: results,
                  emptyMessage: 'No chemical or apparatus matches that search.',
                  onOpen: widget.onOpen,
                ),
        ),
      ],
    );
  }
}

class _GlobalResult {
  const _GlobalResult({
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
    required this.quantity,
    required this.unit,
    required this.status,
    this.searchText = '',
  });

  final ItemKind kind;
  final String id;
  final String name;
  final String subtitle;
  final double quantity;
  final String unit;
  final StockState status;
  final String searchText;
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.results,
    required this.emptyMessage,
    required this.onOpen,
    this.title,
  });

  final String? title;
  final List<_GlobalResult> results;
  final String emptyMessage;
  final void Function(ItemKind kind, String id) onOpen;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return EmptyNotebookState(
        icon: Icons.search_off,
        title: 'nothing here',
        message: emptyMessage,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      itemCount: results.length + (title == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 11),
      itemBuilder: (context, index) {
        if (title != null && index == 0) {
          return PageHeading(title!, fontSize: 31);
        }
        final itemIndex = index - (title == null ? 0 : 1);
        final item = results[itemIndex];
        return NotebookCard(
          onTap: () => onOpen(item.kind, item.id),
          tape: itemIndex % 4 == 0 ? NotebookTape.yellow : NotebookTape.none,
          alternate: itemIndex.isOdd,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(
                item.kind == ItemKind.chemical
                    ? Icons.science_outlined
                    : Icons.precision_manufacturing_outlined,
                color: item.status == StockState.empty
                    ? context.marginRedColor
                    : context.mutedInkColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'ArchitectsDaughter',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.mutedInkColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${formatQuantity(item.quantity)} ${item.unit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.index,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final double value;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StaggerIn(
      index: index,
      child: NotebookCard(
        onTap: onTap,
        tape: switch (index % 4) {
          0 => NotebookTape.yellow,
          1 => NotebookTape.blue,
          2 => NotebookTape.pink,
          _ => NotebookTape.green,
        },
        accent: color,
        rotation: index.isEven ? -.008 : .008,
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
