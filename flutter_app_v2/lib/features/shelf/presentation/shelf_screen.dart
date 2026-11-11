import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shelf_row.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import '../../reports/data/order_list.dart';
import '../../session/presentation/session_screen.dart';
import 'action_sheet.dart';
import 'edit_item_sheet.dart';
import 'item_sheet.dart';
import 'qr_labels_screen.dart';

/// One shelf. Chemicals and apparatus share this screen; the differences are
/// the title, the subtitle field, and QR labels being chemical-only.
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({required this.kind, super.key});

  final ItemKind kind;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  final _search = TextEditingController();
  ConsumptionLog? _undo;
  bool _showHint = false;

  /// Narrowing the shelf without typing: the three questions actually asked of
  /// a store room ("what needs ordering", "what has run out") are one tap.
  _Filter _filter = _Filter.all;
  int _undoToken = 0;

  bool get _isChemical => widget.kind == ItemKind.chemical;

  @override
  void initState() {
    super.initState();
    _maybeShowHint();
  }

  /// Swiping is the one gesture nobody finds by accident, and a shelf with no
  /// hint looks read-only. Shown on the first shelf opened, then never again.
  Future<void> _maybeShowHint() async {
    final preferences = await SharedPreferences.getInstance();
    final seen = preferences.getBool('shelf_gestures_hint_seen_v2') ?? false;
    if (seen || !mounted) return;
    setState(() => _showHint = true);
  }

  Future<void> _dismissHint() async {
    setState(() => _showHint = false);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('shelf_gestures_hint_seen_v2', true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ItemView> _items(InventoryState state) {
    final query = _search.text.trim().toLowerCase();
    final views = _isChemical
        ? state.chemicals.map(ItemView.fromChemical)
        : state.apparatus.map(ItemView.fromApparatus);
    final filtered = views.where((item) {
      if (_filter == _Filter.order && item.metrics.signal == StockSignal.fine) {
        return false;
      }
      if (_filter == _Filter.empty && item.quantity > 0) return false;
      if (query.isEmpty) return true;
      // Formula and category are searched too: people think "NaCl", not
      // "Sodium Chloride".
      final haystack =
          '${item.name} ${item.subtitle} ${item.notes}'.toLowerCase();
      return haystack.contains(query);
    }).toList();
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final items = _items(state);

    // Only empty items, or items low against a level you actually set, count as
    // needing attention.
    final attention = items
        .where((item) => item.metrics.signal != StockSignal.fine)
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
                  title: _isChemical ? 'chemicals' : 'apparatus',
                  attention: attention,
                  total: state.chemicals.length + state.apparatus.length,
                  search: _search,
                  filter: _filter,
                  onFilter: (value) => setState(() => _filter = value),
                  onSearchChanged: (_) => setState(() {}),
                  onMenu: () => _openMenu(context, ref),
                  onShowOrder: () => setState(() => _filter = _Filter.order),
                ),
              ),
              if (_showHint && items.isNotEmpty)
                SliverToBoxAdapter(
                  child: _SwipeHint(
                    onDismiss: _dismissHint,
                  ),
                ),
              if (state.error != null || state.pendingCount > 0)
                SliverToBoxAdapter(
                  child: _SyncNotice(
                    pending: state.pendingCount > 0,
                    message: state.pendingCount > 0
                        ? '${state.pendingCount} waiting to upload'
                        : state.error!,
                  ),
                ),
              if (state.loading && items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyShelf(
                    searching: _search.text.trim().isNotEmpty,
                    isChemical: _isChemical,
                    onAdd: () => _addItem(context, ref),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      Widget row(BuildContext context, int index) {
                        final item = items[index];
                        return ShelfRowIn(
                          key: ValueKey(item.id),
                          index: index,
                          child: ShelfRow(
                            item: item,
                            compact: ref.watch(preferencesProvider).compactRows,
                            onTap: () => _openDetail(context, item),
                            onSwipe: (swipe) => _log(
                              context,
                              ref,
                              item,
                              swipe == RowSwipe.use
                                  ? (_isChemical
                                        ? InventoryAction.consume
                                        : InventoryAction.breakage)
                                  : InventoryAction.restock,
                            ),
                            onLongPress: () => _rowActions(context, ref, item),
                          ),
                        );
                      }

                      // At large text sizes use natural-height rows instead of
                      // forcing text into a fixed-height grid cell.
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      if (constraints.crossAxisExtent >= 700 && scale <= 1.2) {
                        final compact = ref.watch(preferencesProvider).compactRows;
                        return SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            row,
                            childCount: items.length,
                          ),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            mainAxisExtent: (compact ? 82 : 115) * scale,
                          ),
                        );
                      }
                      return SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: row,
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
            log: _undo,
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
    ItemView item,
    InventoryAction action,
  ) async {
    final log = await showActionSheet(
      context,
      ref,
      item: item,
      action: action,
    );
    if (log != null) _offerUndo(log);
  }

  /// Five seconds to take it back, with the row's own undo — the log is removed
  /// and the quantity restored, rather than a compensating entry being written.
  void _offerUndo(ConsumptionLog log) {
    _undoToken++;
    final token = _undoToken;
    setState(() => _undo = log);
    // Deliberately no timer: a bar that vanishes while you are still reading it
    // is worse than one you dismiss. It clears on the next action, on undo, or
    // on the cross.
    assert(token == _undoToken);
  }

  Future<void> _performUndo() async {
    final log = _undo;
    if (log == null) return;
    _undoToken++;
    setState(() => _undo = null);
    HapticFeedback.mediumImpact();
    try {
      await ref.read(inventoryProvider.notifier).undoAction(log);
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
    ItemView item,
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
              title: Text(
                item.isChemical ? 'Log use' : 'Log breakage',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _log(
                  context,
                  ref,
                  item,
                  item.isChemical
                      ? InventoryAction.consume
                      : InventoryAction.breakage,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Restock'),
              onTap: () {
                Navigator.pop(sheetContext);
                _log(context, ref, item, InventoryAction.restock);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Set order level'),
              subtitle: const Text('When should this show as low?'),
              onTap: () {
                Navigator.pop(sheetContext);
                showOrderLevelSheet(context, item: item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Open item'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openDetail(context, item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, ItemView item) =>
      showItemSheet(context, itemId: item.id, kind: item.kind);

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.lab.bone,
      builder: (_) => _AddItemSheet(kind: widget.kind),
    );
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.lab.bone,
      builder: (_) => _MenuSheet(
        kind: widget.kind,
        onAdd: () => _addItem(context, ref),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Which slice of the shelf is on screen.
enum _Filter { all, order, empty }

/// The top of a shelf.
///
/// The largest words on screen state a fact and act as a filter, because the
/// first question in front of a store room is "does anything need ordering?" —
/// not "what is this app called". Search is always visible: it was previously
/// behind an icon, which hid the fastest way to find one bottle among forty.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.attention,
    required this.total,
    required this.search,
    required this.filter,
    required this.onFilter,
    required this.onSearchChanged,
    required this.onMenu,
    required this.onShowOrder,
  });

  final String title;
  final int attention;
  final int total;
  final TextEditingController search;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMenu;
  final VoidCallback onShowOrder;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final calm = attention == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  style: context.label.copyWith(letterSpacing: 1.1),
                ),
              ),
              IconButton(
                tooltip: 'More',
                onPressed: onMenu,
                icon: Icon(Icons.more_horiz, size: 20, color: lab.soft),
              ),
            ],
          ),
          // The headline is a control: it says what the shelf needs and takes
          // you to exactly those rows.
          Semantics(
            button: !calm,
            label: calm
                ? 'Nothing needs ordering'
                : '$attention need attention, show them',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: calm ? null : onShowOrder,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        calm
                            ? 'Everything above its level'
                            : '$attention ${attention == 1 ? 'needs' : 'need'} '
                                  'ordering',
                        style: TextStyle(
                          fontSize: LabType.display,
                          height: 1.04,
                          letterSpacing: -1.4,
                          fontWeight: FontWeight.w600,
                          color: calm ? lab.ink : lab.clay,
                        ),
                      ),
                    ),
                    if (!calm)
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: lab.clay.withValues(alpha: .8),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$total ${title == 'chemicals' ? 'reagents' : 'pieces'} on this '
            'shelf',
            style: context.aside,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: onSearchChanged,
                  style: const TextStyle(fontSize: LabType.small),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name, formula or note',
                    prefixIcon: Icon(Icons.search, size: 17, color: lab.soft),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close, size: 15),
                            onPressed: () {
                              search.clear();
                              onSearchChanged('');
                            },
                          ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add $title',
                onPressed: onMenu,
                icon: Icon(Icons.add, size: 20, color: lab.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'ALL',
                  selected: filter == _Filter.all,
                  onTap: () => onFilter(_Filter.all),
                ),
                const SizedBox(width: 7),
                _FilterChip(
                  label: 'ORDER',
                  selected: filter == _Filter.order,
                  onTap: () => onFilter(_Filter.order),
                ),
                const SizedBox(width: 7),
                _FilterChip(
                  label: 'EMPTY',
                  selected: filter == _Filter.empty,
                  onTap: () => onFilter(_Filter.empty),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? lab.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? lab.ink : lab.hair),
          ),
          child: Text(
            label,
            style: context.label.copyWith(
              fontSize: LabType.micro,
              color: selected ? lab.bone : lab.soft,
            ),
          ),
        ),
      ),
    );
  }
}

/// One-time advice about the swipe, dismissed with a tap.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onDismiss,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: lab.wash(lab.sage),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: lab.wash(lab.sage, .4)),
          ),
          child: Row(
            children: [
              Icon(Icons.swipe, size: 17, color: lab.sage),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Swipe to open a use or restock panel; nothing is saved '
                  'until you confirm. Hold a row for more actions.',
                  style: context.aside.copyWith(
                    fontSize: LabType.small + 1,
                    color: lab.sage,
                  ),
                ),
              ),
              Icon(Icons.close, size: 15, color: lab.sage),
            ],
          ),
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
  const _EmptyShelf({
    required this.searching,
    required this.isChemical,
    required this.onAdd,
  });

  final bool searching;
  final bool isChemical;
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
              child: CustomPaint(painter: _EmptyJarPainter(color: lab.hair)),
            ),
            const SizedBox(height: 18),
            Text(
              searching
                  ? 'Nothing matches.'
                  : (isChemical ? 'An empty shelf.' : 'No apparatus yet.'),
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
                  : 'Add your first item and the jar fills itself in.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: lab.soft),
            ),
            const SizedBox(height: 18),
            if (!searching)
              FilledButton(
                onPressed: onAdd,
                child: Text(isChemical ? 'Add a reagent' : 'Add apparatus'),
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .28, 1, size.width * .44, 7),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyJarPainter old) => old.color != color;
}

class _UndoBar extends StatelessWidget {
  const _UndoBar({
    required this.log,
    required this.onUndo,
    required this.onDismiss,
  });

  final ConsumptionLog? log;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final visible = log != null;
    final isUse = log?.action != InventoryAction.restock;

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
                      isUse ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 15,
                      color: lab.bone.withValues(alpha: .7),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        log == null
                            ? ''
                            : 'Logged ${formatQuantity(log!.amount)} '
                                  '${log!.action.name}',
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
// Sheets
// ---------------------------------------------------------------------------

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet({required this.kind});

  final ItemKind kind;

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _detail = TextEditingController();
  final _quantity = TextEditingController();
  final _limit = TextEditingController();
  String _unit = 'mL';
  String _category = 'glassware';
  bool _saving = false;

  static const _units = ['mL', 'L', 'g', 'mg', 'kg', 'drops', 'pcs'];
  static const _categories = [
    'glassware',
    'balances',
    'heating',
    'measurement',
    'other',
  ];

  bool get _isChemical => widget.kind == ItemKind.chemical;

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    _quantity.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    setState(() => _saving = true);
    final quantity = double.parse(_quantity.text.trim());
    final threshold = double.tryParse(_limit.text.trim()) ?? 0;
    try {
      if (_isChemical) {
        await ref
            .read(inventoryProvider.notifier)
            .addChemical(
              name: _name.text,
              formula: _detail.text,
              unit: _unit,
              quantity: quantity,
              threshold: threshold,
              notes: '',
            );
      } else {
        await ref
            .read(inventoryProvider.notifier)
            .addApparatus(
              name: _name.text,
              category: _category,
              quantity: quantity,
              threshold: threshold,
              notes: '',
            );
      }
      if (mounted) Navigator.pop(context);
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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          children: [
            Text(
              _isChemical ? 'New reagent' : 'New apparatus',
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
            if (_isChemical)
              TextFormField(
                controller: _detail,
                decoration: const InputDecoration(labelText: 'Formula'),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
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
                if (_isChemical) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: _units
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(unit),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _unit = value);
                      },
                    ),
                  ),
                ],
              ],
            ),
            TextFormField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Order level (optional)',
                helperText: 'Leave empty and it stays fine until empty',
                suffixText: _isChemical ? _unit : 'pcs',
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

/// Actions on this shelf. Preferences live in Settings — one home each, so the
/// same switch never appears in two places with two behaviours.
class _MenuSheet extends ConsumerWidget {
  const _MenuSheet({required this.kind, required this.onAdd});

  final ItemKind kind;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final inventory = ref.watch(inventoryProvider);
    final compact = ref.watch(preferencesProvider).compactRows;
    final isChemical = kind == ItemKind.chemical;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.add, size: 20),
            title: Text(isChemical ? 'Add a reagent' : 'Add apparatus'),
            onTap: () {
              Navigator.pop(context);
              onAdd();
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, size: 20),
            title: const Text('Log a whole session'),
            subtitle: const Text('Several items, one screen'),
            onTap: () {
              Navigator.pop(context);
              openSession(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined, size: 20),
            title: const Text('Share the order list'),
            subtitle: Text(
              inventory.needsOrdering.isEmpty
                  ? 'Nothing needs ordering'
                  : '${inventory.needsOrdering.length} to order',
            ),
            onTap: inventory.needsOrdering.isEmpty
                ? null
                : () {
                    Navigator.pop(context);
                    shareOrderList(context, inventory.needsOrdering);
                  },
          ),
          if (isChemical)
            ListTile(
              leading: const Icon(Icons.qr_code_2, size: 20),
              title: const Text('Print QR labels'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QrLabelScreen(),
                  ),
                );
              },
            ),
          const Divider(),
          SwitchListTile(
            secondary: Icon(
              compact ? Icons.view_headline : Icons.view_agenda_outlined,
              size: 20,
              color: lab.soft,
            ),
            title: const Text('Compact rows'),
            subtitle: Text(
              compact
                  ? 'Fitting about twice as many per screen'
                  : 'Roomier rows, with jar ticks',
            ),
            value: compact,
            onChanged: ref.read(preferencesProvider.notifier).setCompactRows,
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
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
