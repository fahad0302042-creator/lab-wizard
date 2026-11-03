import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_jar.dart';
import '../../../core/widgets/jar_metrics.dart';
import '../../../core/widgets/shelf_row.dart';
import '../../inventory/domain/models.dart';
import 'action_sheet.dart';

class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key});

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  final _search = TextEditingController();
  LoggedAction? _undo;
  Timer? _undoTimer;
  bool _searching = false;

  @override
  void dispose() {
    _undoTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final query = _search.text.trim().toLowerCase();

    final chemicals = state.chemicals.where((item) {
      if (query.isEmpty) return true;
      final haystack = '${item.name} ${item.formula} ${item.notes}';
      return haystack.toLowerCase().contains(query);
    }).toList()..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // Only items that are empty, or low against a level you actually set, count
    // as needing a look. Items with no level are never counted — otherwise the
    // number cries wolf and stops being trusted.
    final attention = state.chemicals.where((item) {
      final metrics = jarMetrics(
        quantity: item.quantity,
        initialQuantity: item.initialQuantity,
        threshold: item.lowStockThreshold,
      );
      return metrics.signal != StockSignal.fine;
    }).length;

    final usedToday = state.logs
        .where(
          (log) =>
              log.action == InventoryAction.consume &&
              localDayKey(log.loggedAt) == localDayKey(DateTime.now()),
        )
        .length;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: ref.read(inventoryProvider.notifier).refresh,
          color: lab.sage,
          backgroundColor: lab.card,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  attention: attention,
                  total: state.chemicals.length,
                  usedToday: usedToday,
                  searching: _searching,
                  search: _search,
                  onSearchToggle: () {
                    setState(() {
                      _searching = !_searching;
                      if (!_searching) _search.clear();
                    });
                  },
                  onSearchChanged: (_) => setState(() {}),
                  onMenu: () => _openMenu(context, ref),
                ),
              ),
              if (state.error != null || state.pendingCount > 0)
                SliverToBoxAdapter(
                  child: _SyncNotice(
                    message: state.pendingCount > 0
                        ? '${state.pendingCount} '
                              '${state.pendingCount == 1 ? 'change' : 'changes'}'
                              ' waiting to upload'
                        : state.error!,
                    pending: state.pendingCount > 0,
                  ),
                ),
              if (state.loading && state.chemicals.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (chemicals.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyShelf(
                    searching: query.isNotEmpty,
                    onAdd: () => _addItem(context, ref),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  sliver: SliverList.separated(
                    itemCount: chemicals.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final chemical = chemicals[index];
                      return ShelfRowIn(
                        index: index,
                        child: ShelfRow(
                          chemical: chemical,
                          index: index,
                          onTap: () => _openDetail(context, ref, chemical),
                          onUse: () => _log(context, ref, chemical,
                              InventoryAction.consume),
                          onRestock: () => _log(context, ref, chemical,
                              InventoryAction.restock),
                          onFullSwipe: (swipe) => _quickLog(
                            context,
                            ref,
                            chemical,
                            swipe == RowSwipe.use
                                ? InventoryAction.consume
                                : InventoryAction.restock,
                          ),
                          onLongPress: () =>
                              _rowActions(context, ref, chemical),
                        ),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _UndoBar(
            action: _undo,
            onUndo: _performUndo,
            onDismiss: () => setState(() => _undo = null),
          ),
        ),
      ],
    );
  }

  Future<void> _log(
    BuildContext context,
    WidgetRef ref,
    Chemical chemical,
    InventoryAction action,
  ) async {
    final result = await showActionSheet(
      context,
      ref,
      chemical: chemical,
      action: action,
    );
    if (result != null) _offerUndo(result);
  }

  /// Full swipe: commit the amount this item is usually logged at, no sheet.
  Future<void> _quickLog(
    BuildContext context,
    WidgetRef ref,
    Chemical chemical,
    InventoryAction action,
  ) async {
    final logs = ref
        .read(inventoryProvider)
        .logs
        .where(
          (log) =>
              log.itemId == chemical.id &&
              log.action == InventoryAction.consume,
        )
        .toList();
    final amount = action == InventoryAction.restock
        ? 1.0
        : (logs.isNotEmpty ? logs.first.amount : 1.0);
    if (action == InventoryAction.consume && amount > chemical.quantity) {
      return _log(context, ref, chemical, action);
    }
    try {
      await ref
          .read(inventoryProvider.notifier)
          .applyAction(
            itemId: chemical.id,
            itemType: ItemKind.chemical,
            action: action,
            amount: amount,
            note: '',
            date: DateTime.now(),
          );
      _offerUndo(
        LoggedAction(chemical: chemical, action: action, amount: amount),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  void _offerUndo(LoggedAction action) {
    _undoTimer?.cancel();
    setState(() => _undo = action);
    _undoTimer = Timer(LabMotion.undoWindow, () {
      if (mounted) setState(() => _undo = null);
    });
  }

  Future<void> _performUndo() async {
    final action = _undo;
    if (action == null) return;
    _undoTimer?.cancel();
    setState(() => _undo = null);
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(inventoryProvider.notifier)
          .applyAction(
            itemId: action.chemical.id,
            itemType: ItemKind.chemical,
            action: action.inverse,
            amount: action.amount,
            note: 'undo',
            date: DateTime.now(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Undone')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _rowActions(
    BuildContext context,
    WidgetRef ref,
    Chemical chemical,
  ) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.lab.bone,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Log use'),
              onTap: () {
                Navigator.pop(sheetContext);
                _log(context, ref, chemical, InventoryAction.consume);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Restock'),
              onTap: () {
                Navigator.pop(sheetContext);
                _log(context, ref, chemical, InventoryAction.restock);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Set order level'),
              subtitle: const Text('When should this show as low?'),
              onTap: () {
                Navigator.pop(sheetContext);
                _setLimit(context, ref, chemical);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Open item'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openDetail(context, ref, chemical);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _setLimit(
    BuildContext context,
    WidgetRef ref,
    Chemical chemical,
  ) async {
    final controller = TextEditingController(
      text: chemical.lowStockThreshold > 0
          ? formatQuantity(chemical.lowStockThreshold)
          : '',
    );
    final saved = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Order level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell me when ${chemical.name} is running low and I\'ll flag it. '
              'Leave it empty and the jar stays full-looking until it\'s '
              'empty.',
              style: TextStyle(color: dialogContext.lab.soft, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Flag below',
                suffixText: chemical.unit,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()) ?? 0,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    try {
      await ref
          .read(inventoryProvider.notifier)
          .updateItem(
            type: ItemKind.chemical,
            id: chemical.id,
            changes: {'low_stock_threshold': saved},
          );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _openDetail(
    BuildContext context,
    WidgetRef ref,
    Chemical chemical,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.lab.bone,
      builder: (_) => _ItemSheet(chemicalId: chemical.id),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.lab.bone,
      builder: (_) => const _AddItemSheet(),
    );
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.lab.bone,
      builder: (_) => const _MenuSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.attention,
    required this.total,
    required this.usedToday,
    required this.searching,
    required this.search,
    required this.onSearchToggle,
    required this.onSearchChanged,
    required this.onMenu,
  });

  final int attention;
  final int total;
  final int usedToday;
  final bool searching;
  final TextEditingController search;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMMM').format(now),
                  style: context.aside,
                ),
              ),
              IconButton(
                tooltip: 'Search',
                onPressed: onSearchToggle,
                icon: Icon(
                  searching ? Icons.close : Icons.search,
                  size: 20,
                  color: lab.soft,
                ),
              ),
              IconButton(
                tooltip: 'More',
                onPressed: onMenu,
                icon: Icon(Icons.more_horiz, size: 20, color: lab.soft),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              attention == 0 ? 'Good shelves.' : 'Almost there.',
              style: TextStyle(
                fontSize: 31,
                height: 1.04,
                letterSpacing: -1.4,
                fontWeight: FontWeight.w600,
                color: lab.ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              attention == 0
                  ? 'Nothing needs a look.'
                  : '$attention '
                        '${attention == 1 ? 'jar needs' : 'jars need'}' 
                        'a look.',
              style: TextStyle(
                fontSize: 31,
                height: 1.04,
                letterSpacing: -1.4,
                fontWeight: FontWeight.w600,
                color: attention == 0 ? lab.sage : lab.clay,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: lab.hair, height: 1),
          Row(
            children: [
              _Stat(value: '$total', label: 'Reagents'),
              _Stat(value: '$attention', label: 'To order'),
              _Stat(value: '$usedToday', label: 'Used today', last: true),
            ],
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: search,
                autofocus: true,
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Name, formula or note',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.last = false,
  });

  final String value;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(right: BorderSide(color: lab.hair, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CountUp(
              value: double.tryParse(value) ?? 0,
              builder: (context, animated) => Text(
                formatQuantity(animated),
                style: TextStyle(
                  fontSize: 21,
                  height: 1.1,
                  letterSpacing: -.8,
                  fontWeight: FontWeight.w600,
                  color: lab.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: context.label.copyWith(fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.message, required this.pending});

  final String message;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Icon(
            pending ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined,
            size: 15,
            color: lab.clay,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: lab.clay),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.searching, required this.onAdd});

  final bool searching;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 52,
              height: 64,
              child: CustomPaint(
                painter: _EmptyJarPainter(color: lab.hair),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              searching ? 'Nothing matches.' : 'An empty shelf.',
              style: TextStyle(
                fontSize: 21,
                letterSpacing: -.6,
                fontWeight: FontWeight.w600,
                color: lab.ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              searching
                  ? 'Try another name or formula.'
                  : 'Add your first reagent and the jar will fill itself in.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: lab.soft),
            ),
            const SizedBox(height: 18),
            if (!searching)
              FilledButton(
                onPressed: onAdd,
                child: const Text('Add a reagent'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyJarPainter extends CustomPainter {
  const _EmptyJarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 8, size.width - 2, size.height - 9),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .28, 1, size.width * .44, 7),
      const Radius.circular(2),
    );
    canvas.drawRRect(cap, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _EmptyJarPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Undo
// ---------------------------------------------------------------------------

class _UndoBar extends StatelessWidget {
  const _UndoBar({
    required this.action,
    required this.onUndo,
    required this.onDismiss,
  });

  final LoggedAction? action;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final visible = action != null;
    final isUse = action?.action != InventoryAction.restock;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: Offset(0, visible ? 0 : 1.4),
        duration: LabMotion.of(context, LabMotion.standard),
        curve: LabMotion.enterCurve,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: LabMotion.of(context, LabMotion.quick),
          child: Material(
            color: lab.ink,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                child: Row(
                  children: [
                    Icon(
                      isUse
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 15,
                      color: lab.bone.withValues(alpha: .7),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        action == null
                            ? ''
                            : '${isUse ? 'Used' : 'Added'} '
                                  '${formatQuantity(action!.amount)} '
                                  '${action!.chemical.unit} · '
                                  '${action!.chemical.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: lab.bone),
                      ),
                    ),
                    TextButton(
                      onPressed: onUndo,
                      style: TextButton.styleFrom(
                        foregroundColor: lab.bone,
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text('Undo'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item sheet, add sheet and menu
// ---------------------------------------------------------------------------

class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.chemicalId});

  final String chemicalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final chemical = state.chemicals.firstWhere(
      (item) => item.id == chemicalId,
      orElse: () => state.chemicals.first,
    );
    final metrics = jarMetrics(
      quantity: chemical.quantity,
      initialQuantity: chemical.initialQuantity,
      threshold: chemical.lowStockThreshold,
    );
    final logs = state.logs
        .where((log) => log.itemId == chemicalId)
        .take(6)
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .42,
      maxChildSize: .94,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
                      chemical.name,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.06,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w600,
                        color: lab.ink,
                      ),
                    ),
                    if (chemical.formula.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          chemical.formula,
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
                formatQuantity(chemical.quantity),
                style: TextStyle(
                  fontSize: 40,
                  height: .95,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w600,
                  color: lab.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  chemical.unit,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final result = await showActionSheet(
                      context,
                      ref,
                      chemical: chemical,
                      action: InventoryAction.consume,
                    );
                    if (result != null && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Log use'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final result = await showActionSheet(
                      context,
                      ref,
                      chemical: chemical,
                      action: InventoryAction.restock,
                    );
                    if (result != null && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
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
              (log) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
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
          if (chemical.notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('NOTES', style: context.label),
            const SizedBox(height: 6),
            Text(
              chemical.notes,
              style: TextStyle(fontSize: 13, height: 1.5, color: lab.soft),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet();

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _formula = TextEditingController();
  final _quantity = TextEditingController();
  final _limit = TextEditingController();
  String _unit = 'mL';
  bool _saving = false;

  static const _units = ['mL', 'L', 'g', 'mg', 'kg', 'drops', 'pcs'];

  @override
  void dispose() {
    _name.dispose();
    _formula.dispose();
    _quantity.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .addChemical(
            name: _name.text,
            formula: _formula.text,
            unit: _unit,
            quantity: double.parse(_quantity.text.trim()),
            threshold: double.tryParse(_limit.text.trim()) ?? 0,
            notes: '',
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          children: [
            Text(
              'New reagent',
              style: TextStyle(
                fontSize: 26,
                letterSpacing: -1,
                fontWeight: FontWeight.w600,
                color: lab.ink,
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Give it a name' : null,
            ),
            TextFormField(
              controller: _formula,
              decoration: const InputDecoration(labelText: 'Formula'),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'How much do you have',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      return parsed == null || parsed <= 0
                          ? 'Enter an amount'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: _units
                        .map(
                          (unit) =>
                              DropdownMenuItem(value: unit, child: Text(unit)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _unit = value);
                    },
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Order level (optional)',
                helperText: 'Leave empty and it stays full-looking until empty',
                suffixText: _unit,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add to shelf'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuSheet extends ConsumerWidget {
  const _MenuSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final preferences = ref.watch(preferencesProvider);
    final inventory = ref.watch(inventoryProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Desk-lamp mode'),
            subtitle: const Text('Dark paper for the evening shift'),
            value: preferences.themeMode == ThemeMode.dark,
            onChanged: (value) => ref
                .read(preferencesProvider.notifier)
                .setTheme(value ? ThemeMode.dark : ThemeMode.light),
          ),
          SwitchListTile(
            title: const Text('Reduce motion'),
            subtitle: const Text('Instant transitions, no sloshing'),
            value: preferences.reduceMotion,
            onChanged: ref.read(preferencesProvider.notifier).setReduceMotion,
          ),
          ListTile(
            leading: const Icon(Icons.sync, size: 20),
            title: const Text('Sync now'),
            subtitle: Text(
              inventory.pendingCount > 0
                  ? '${inventory.pendingCount} waiting to upload'
                  : 'Everything is uploaded',
            ),
            onTap: () => ref.read(inventoryProvider.notifier).refresh(),
          ),
          ListTile(
            leading: Icon(Icons.logout, size: 20, color: lab.berry),
            title: Text('Sign out', style: TextStyle(color: lab.berry)),
            onTap: () async {
              final pending = inventory.pendingCount;
              if (pending > 0) {
                final go = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Still uploading'),
                    content: Text(
                      '$pending change${pending == 1 ? '' : 's'} haven\'t '
                      'reached the server yet. Signing out now would lose '
                      'them.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Stay'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Wait, keep them'),
                      ),
                    ],
                  ),
                );
                if (go == true && context.mounted) {
                  await ref.read(inventoryProvider.notifier).refresh();
                }
                return;
              }
              await ref.read(authProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
