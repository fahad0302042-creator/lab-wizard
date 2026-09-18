import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';
import 'inventory_sheets.dart';

enum _StockFilter { all, low, empty }

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({required this.kind, super.key});

  final ItemKind kind;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  _StockFilter _filter = _StockFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final query = _searchController.text.trim().toLowerCase();
    final items = widget.kind == ItemKind.chemical
        ? state.chemicals
              .where(
                (item) => _matches(
                  item.name,
                  item.formula,
                  item.notes,
                  item.stockState,
                  query,
                ),
              )
              .map<_InventoryView>(
                (item) => _InventoryView(
                  id: item.id,
                  name: item.name,
                  subtitle: item.formula.isEmpty ? 'No formula' : item.formula,
                  quantity: item.quantity,
                  unit: item.unit,
                  progress: item.stockProgress,
                  status: item.stockState,
                ),
              )
              .toList()
        : state.apparatus
              .where(
                (item) => _matches(
                  item.name,
                  item.category,
                  item.notes,
                  item.stockState,
                  query,
                ),
              )
              .map<_InventoryView>(
                (item) => _InventoryView(
                  id: item.id,
                  name: item.name,
                  subtitle: item.category,
                  quantity: item.quantity,
                  unit: 'pcs',
                  progress: item.stockProgress,
                  status: item.stockState,
                ),
              )
              .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-${widget.kind.name}',
        onPressed: () => showAddItemSheet(context, ref, widget.kind),
        icon: const Icon(Icons.add),
        label: Text(
          widget.kind == ItemKind.chemical ? 'Chemical' : 'Apparatus',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(inventoryProvider.notifier).refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(42, 18, 18, 10),
              sliver: SliverList.list(
                children: [
                  PageHeading(
                    widget.kind == ItemKind.chemical
                        ? 'chemical shelf'
                        : 'apparatus shelf',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: widget.kind == ItemKind.chemical
                          ? 'Name, formula, or note…'
                          : 'Name, category, or note…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_StockFilter>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _StockFilter.all,
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: _StockFilter.low,
                          label: Text('Low'),
                        ),
                        ButtonSegment(
                          value: _StockFilter.empty,
                          label: Text('Out'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (value) =>
                          setState(() => _filter = value.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${items.length} item${items.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: context.mutedInkColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (state.loading && items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyNotebookState(
                  icon: widget.kind == ItemKind.chemical
                      ? Icons.science_outlined
                      : Icons.precision_manufacturing_outlined,
                  title: query.isEmpty
                      ? 'this shelf is empty'
                      : 'nothing matches',
                  message: query.isEmpty
                      ? 'Tap the add button to create your first item.'
                      : 'Try another search or filter.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(42, 6, 18, 110),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => StaggerIn(
                    index: index,
                    child: _InventoryCard(
                      item: items[index],
                      kind: widget.kind,
                      onTap: () => showItemDetailSheet(
                        context,
                        ref,
                        widget.kind,
                        items[index].id,
                      ),
                      onConsume: () => showInventoryActionSheet(
                        context,
                        ref,
                        kind: widget.kind,
                        itemId: items[index].id,
                        action: widget.kind == ItemKind.chemical
                            ? InventoryAction.consume
                            : InventoryAction.breakage,
                      ),
                      onRestock: () => showInventoryActionSheet(
                        context,
                        ref,
                        kind: widget.kind,
                        itemId: items[index].id,
                        action: InventoryAction.restock,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _matches(
    String name,
    String subtitle,
    String notes,
    StockState status,
    String query,
  ) {
    if (_filter == _StockFilter.low && status != StockState.low) return false;
    if (_filter == _StockFilter.empty && status != StockState.empty) {
      return false;
    }
    return query.isEmpty ||
        '$name $subtitle $notes'.toLowerCase().contains(query);
  }
}

class _InventoryView {
  const _InventoryView({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.quantity,
    required this.unit,
    required this.progress,
    required this.status,
  });

  final String id;
  final String name;
  final String subtitle;
  final double quantity;
  final String unit;
  final double progress;
  final StockState status;
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.kind,
    required this.onTap,
    required this.onConsume,
    required this.onRestock,
  });

  final _InventoryView item;
  final ItemKind kind;
  final VoidCallback onTap;
  final VoidCallback onConsume;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('${kind.name}-${item.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          onRestock();
        } else {
          onConsume();
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: LabColors.green,
        icon: Icons.add,
        text: 'restock',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: kind == ItemKind.chemical
            ? LabColors.amber
            : LabColors.marginRed,
        icon: kind == ItemKind.chemical
            ? Icons.remove
            : Icons.broken_image_outlined,
        text: kind == ItemKind.chemical ? 'consume' : 'breakage',
      ),
      child: Hero(
        tag: '${kind.name}-${item.id}',
        child: NotebookCard(
          onTap: onTap,
          accent: statusColor(item.status),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.subtitle,
                          style: TextStyle(color: context.mutedInkColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedQuantity(
                    item.quantity,
                    suffix: ' ${item.unit}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              StockBar(progress: item.progress, status: item.status),
              const SizedBox(height: 9),
              Row(
                children: [
                  StatusBadge(item.status),
                  const Spacer(),
                  Text(
                    'Swipe to update',
                    style: TextStyle(
                      color: context.mutedInkColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.text,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft
            ? [
                Icon(icon, color: color),
                const SizedBox(width: 7),
                Text(
                  text,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ]
            : [
                Text(
                  text,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 7),
                Icon(icon, color: color),
              ],
      ),
    );
  }
}
