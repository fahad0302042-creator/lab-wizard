import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../settings/presentation/settings_screen.dart';
import '../domain/models.dart';
import 'batch_sheets.dart';
import 'inventory_sheets.dart';

enum _StockFilter { all, low, critical }

enum _InventorySort { name, quantity, status }

enum _ShelfMenu { select, batchConsume, printLabels, settings }

/// Actions offered for a multi-selection (BATCH-01/02/04, QR-01).
enum SelectionAction { restock, threshold, labels, delete }

/// Letters offered by the quick navigation strip. Names that do not start
/// with a Latin letter are grouped under `#`.
const alphabetIndexLetters = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
  '#',
];

/// The index letter used for an item name (UX-02).
String indexLetterFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '#';
  final first = trimmed[0].toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(first) ? first : '#';
}

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({required this.kind, super.key});

  final ItemKind kind;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _itemKeys = <String, GlobalKey>{};
  _StockFilter _filter = _StockFilter.all;
  _InventorySort _sort = _InventorySort.name;
  bool _printingLabels = false;
  bool _headingCollapsed = false;
  bool _selectionMode = false;
  final _selected = <String>{};
  List<_InventoryView> _visibleItems = const [];

  static const _detailedGap = 18.0;
  static const _minimumItemsForIndex = 8;

  static const _tapes = [
    NotebookTape.yellow,
    NotebookTape.blue,
    NotebookTape.green,
    NotebookTape.pink,
    NotebookTape.none,
    NotebookTape.none,
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isChemical => widget.kind == ItemKind.chemical;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final density = ref.watch(
      preferencesProvider.select((value) => value.inventoryDensity),
    );
    final compact = density == InventoryDensity.compact;
    final query = _searchController.text.trim().toLowerCase();
    final allItems = _isChemical
        ? state.chemicals.map(_InventoryView.chemical).toList()
        : state.apparatus.map(_InventoryView.apparatus).toList();

    final items = allItems.where((item) => _matches(item, query)).toList()
      ..sort(
        (a, b) => switch (_sort) {
          _InventorySort.name => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
          _InventorySort.quantity => b.quantity.compareTo(a.quantity),
          _InventorySort.status => _statusRank(
            a.status,
          ).compareTo(_statusRank(b.status)),
        },
      );
    _visibleItems = items;
    if (_selected.isNotEmpty) {
      final existing = {for (final item in allItems) item.id};
      _selected.retainWhere(existing.contains);
    }
    final visibleIds = {for (final item in items) item.id};
    final allVisibleSelected =
        items.isNotEmpty && visibleIds.every(_selected.contains);
    final showIndex = allItems.length >= _minimumItemsForIndex;
    final availableLetters = {for (final item in items) item.letter};
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return PopScope(
      // Back leaves selection mode before it leaves the shelf.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.small(
        heroTag: 'add-${widget.kind.name}',
        tooltip: _isChemical ? 'Add chemical' : 'Add apparatus',
        onPressed: () => showAddItemSheet(context, ref, widget.kind),
        elevation: 2,
        backgroundColor: context.cardColor,
        foregroundColor: context.inkColor,
        shape: CircleBorder(
          side: BorderSide(color: context.inkColor, width: 2),
        ),
        child: const Icon(Icons.add, size: 27),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // UX-03: the handwritten heading collapses once the list scrolls so
          // the search, filter, and sort controls stay reachable without
          // hiding most of the shelf.
          AnimatedSize(
            duration: motion,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _headingCollapsed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(54, 18, 20, 0),
                    child: PageHeading(
                      _isChemical ? 'chemicals shelf' : 'apparatus shelf',
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(54, 6, 20, 6),
            child: _ShelfControls(
              kind: widget.kind,
              searchController: _searchController,
              query: query,
              filter: _filter,
              sort: _sort,
              compact: compact,
              shown: items.length,
              total: allItems.length,
              printingLabels: _printingLabels,
              selectionMode: _selectionMode,
              selectedCount: _selected.length,
              allVisibleSelected: allVisibleSelected,
              onExitSelection: _exitSelection,
              onSelectAllVisible: () => setState(() {
                if (allVisibleSelected) {
                  _selected.removeAll(visibleIds);
                } else {
                  _selected.addAll(visibleIds);
                }
              }),
              onSearchChanged: () => setState(() {}),
              onClearSearch: () {
                _searchController.clear();
                setState(() {});
              },
              onFilter: (value) => setState(() => _filter = value),
              onSort: (value) => setState(() => _sort = value),
              onToggleDensity: () => ref
                  .read(preferencesProvider.notifier)
                  .setInventoryDensity(
                    compact
                        ? InventoryDensity.detailed
                        : InventoryDensity.compact,
                  ),
              onMenu: (value) => _handleMenu(value, state),
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _handleScroll,
                  child: RefreshIndicator(
                    onRefresh: ref.read(inventoryProvider.notifier).refresh,
                    child: CustomScrollView(
                      key: PageStorageKey('inventory-${widget.kind.name}'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (state.loading && allItems.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyNotebookState(
                              icon: _isChemical
                                  ? Icons.science_outlined
                                  : Icons.precision_manufacturing_outlined,
                              title: query.isEmpty
                                  ? 'empty shelf'
                                  : 'nothing matches',
                              message: query.isEmpty
                                  ? 'Tap the circled + to add your first item.'
                                  : 'Try another search, filter, or sort.',
                              action: CircledNotebookButton(
                                label: _isChemical
                                    ? 'add reagent'
                                    : 'add apparatus',
                                icon: Icons.add,
                                onPressed: () =>
                                    showAddItemSheet(context, ref, widget.kind),
                              ),
                            ),
                          )
                        else ...[
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              54,
                              compact ? 2 : 12,
                              showIndex ? 34 : 20,
                              22,
                            ),
                            sliver: compact
                                ? SliverList.separated(
                                    itemCount: items.length,
                                    separatorBuilder: (_, _) => Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: context.ruledColor,
                                    ),
                                    itemBuilder: (context, index) =>
                                        _buildCompactRow(items, index),
                                  )
                                : SliverList.separated(
                                    itemCount: items.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: _detailedGap),
                                    itemBuilder: (context, index) =>
                                        _buildDetailedCard(items, index),
                                  ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                54,
                                4,
                                20,
                                108,
                              ),
                              child: _AddDoodle(
                                label: _isChemical
                                    ? '~ add new reagent ~'
                                    : '~ add new apparatus ~',
                                onTap: () =>
                                    showAddItemSheet(context, ref, widget.kind),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showIndex && items.isNotEmpty)
                  Positioned(
                    top: 4,
                    right: 0,
                    bottom: 12,
                    child: AlphabetIndex(
                      available: availableLetters,
                      onSelected: _jumpToLetter,
                    ),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: motion,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _selectionMode
                ? _SelectionActionBar(
                    kind: widget.kind,
                    count: _selected.length,
                    busy: _printingLabels,
                    onAction: _handleSelectionAction,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
      ),
    );
  }

  void _enterSelection([String? id]) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = true;
      if (id != null) _selected.add(id);
    });
  }

  void _exitSelection() {
    if (!_selectionMode && _selected.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _handleSelectionAction(SelectionAction action) async {
    final ids = Set<String>.of(_selected);
    if (ids.isEmpty) return;
    switch (action) {
      case SelectionAction.restock:
        await showBatchRestockSheet(context, kind: widget.kind, itemIds: ids);
      case SelectionAction.threshold:
        await showBatchThresholdSheet(
          context,
          kind: widget.kind,
          itemIds: ids,
        );
      case SelectionAction.labels:
        final chemicals = ref
            .read(inventoryProvider)
            .chemicals
            .where((item) => ids.contains(item.id))
            .toList();
        await _printQrLabels(chemicals);
        return;
      case SelectionAction.delete:
        await showBatchDeleteSheet(context, kind: widget.kind, itemIds: ids);
    }
    if (!mounted) return;
    // Items that were deleted disappear from the selection on rebuild; keep
    // the rest selected so a second action can follow.
    setState(() {});
  }

  Widget _buildDetailedCard(List<_InventoryView> items, int index) {
    final item = items[index];
    return KeyedSubtree(
      key: _itemKey(item.id),
      child: StaggerIn(
        index: index,
        child: _InventoryCard(
          item: item,
          index: index,
          tape: _tapes[index % _tapes.length],
          kind: widget.kind,
          selecting: _selectionMode,
          selected: _selected.contains(item.id),
          onTap: () => _selectionMode
              ? _toggleSelected(item.id)
              : _openDetail(item.id),
          onLongPress: () => _selectionMode
              ? _toggleSelected(item.id)
              : _enterSelection(item.id),
          onConsume: () => _openAction(item.id, _primaryAction),
          onRestock: () => _openAction(item.id, InventoryAction.restock),
        ),
      ),
    );
  }

  Widget _buildCompactRow(List<_InventoryView> items, int index) {
    final item = items[index];
    return KeyedSubtree(
      key: _itemKey(item.id),
      child: _CompactRow(
        item: item,
        kind: widget.kind,
        selecting: _selectionMode,
        selected: _selected.contains(item.id),
        onTap: () =>
            _selectionMode ? _toggleSelected(item.id) : _openDetail(item.id),
        onLongPress: () => _selectionMode
            ? _toggleSelected(item.id)
            : _enterSelection(item.id),
        onConsume: () => _openAction(item.id, _primaryAction),
        onRestock: () => _openAction(item.id, InventoryAction.restock),
      ),
    );
  }

  InventoryAction get _primaryAction =>
      _isChemical ? InventoryAction.consume : InventoryAction.breakage;

  GlobalKey _itemKey(String id) => _itemKeys.putIfAbsent(id, GlobalKey.new);

  void _openDetail(String id) =>
      showItemDetailSheet(context, ref, widget.kind, id);

  void _openAction(String id, InventoryAction action) =>
      showInventoryActionSheet(
        context,
        ref,
        kind: widget.kind,
        itemId: id,
        action: action,
      );

  void _handleMenu(_ShelfMenu value, InventoryState state) {
    switch (value) {
      case _ShelfMenu.select:
        _enterSelection();
      case _ShelfMenu.batchConsume:
        showBatchConsumeSheet(context, ref);
      case _ShelfMenu.printLabels:
        _printQrLabels(state.chemicals);
      case _ShelfMenu.settings:
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final pixels = notification.metrics.pixels;
    final collapse = _headingCollapsed ? pixels > 12 : pixels > 40;
    if (collapse != _headingCollapsed) {
      setState(() => _headingCollapsed = collapse);
    }
    return false;
  }

  bool _matches(_InventoryView item, String query) {
    if (_filter == _StockFilter.low && item.status == StockState.healthy) {
      return false;
    }
    if (_filter == _StockFilter.critical && item.status != StockState.empty) {
      return false;
    }
    return query.isEmpty || item.searchText.toLowerCase().contains(query);
  }

  int _statusRank(StockState status) => switch (status) {
    StockState.empty => 0,
    StockState.low => 1,
    StockState.healthy => 2,
  };

  // UX-02: jump to the first item whose name starts with the letter, in the
  // current search/filter/sort order.
  Future<void> _jumpToLetter(String letter) async {
    final items = _visibleItems;
    final target = items.indexWhere((item) => item.letter == letter);
    if (target < 0) return;
    HapticFeedback.selectionClick();
    await _revealIndex(target, items);
  }

  /// Scrolls until [target] is at the top of the list.
  ///
  /// Items that are not built yet have no render object, so the position is
  /// estimated from the items that are built (rows in a mode share one
  /// height, which makes the estimate exact) and refined once the target
  /// exists.
  Future<void> _revealIndex(int target, List<_InventoryView> items) async {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      final targetContext = _itemKey(items[target].id).currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final estimate = _estimateOffset(target, items);
      if (estimate == null) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  double? _estimateOffset(int target, List<_InventoryView> items) {
    RenderBox? first;
    RenderBox? last;
    var firstIndex = -1;
    var lastIndex = -1;
    for (var index = 0; index < items.length; index++) {
      final box = _itemKeys[items[index].id]?.currentContext
          ?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (first == null) {
        first = box;
        firstIndex = index;
      }
      last = box;
      lastIndex = index;
    }
    if (first == null || last == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(first);
    if (viewport == null) return null;
    final firstOffset = viewport.getOffsetToReveal(first, 0).offset;
    final double pitch;
    if (lastIndex != firstIndex) {
      final lastOffset = viewport.getOffsetToReveal(last, 0).offset;
      pitch = (lastOffset - firstOffset) / (lastIndex - firstIndex);
    } else {
      final compact =
          ref.read(preferencesProvider).inventoryDensity ==
          InventoryDensity.compact;
      pitch = first.size.height + (compact ? 1 : _detailedGap);
    }
    return firstOffset + (target - firstIndex) * pitch;
  }

  Future<void> _printQrLabels(List<Chemical> chemicals) async {
    if (chemicals.isEmpty || _printingLabels) return;
    setState(() => _printingLabels = true);
    try {
      final document = pw.Document(title: 'Lab Wizard QR labels');
      for (var offset = 0; offset < chemicals.length; offset += 40) {
        final pageItems = chemicals.skip(offset).take(40).toList();
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (_) => pw.Column(
              children: List.generate(8, (row) {
                return pw.Expanded(
                  child: pw.Row(
                    children: List.generate(5, (column) {
                      final index = row * 5 + column;
                      return pw.Expanded(
                        child: index >= pageItems.length
                            ? pw.SizedBox()
                            : _qrLabel(pageItems[index]),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        );
      }
      await Printing.layoutPdf(
        name: 'Lab-Wizard-QR-Labels.pdf',
        onLayout: (_) => document.save(),
      );
    } finally {
      if (mounted) setState(() => _printingLabels = false);
    }
  }

  pw.Widget _qrLabel(Chemical chemical) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: .45),
      ),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: 'labwizard:chemical:${chemical.qrCode}',
            width: 17 * PdfPageFormat.mm,
            height: 17 * PdfPageFormat.mm,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            chemical.name,
            maxLines: 2,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
          if (chemical.formula.isNotEmpty)
            pw.Text(
              chemical.formula,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
            ),
        ],
      ),
    );
  }
}

class _ShelfControls extends StatelessWidget {
  const _ShelfControls({
    required this.kind,
    required this.searchController,
    required this.query,
    required this.filter,
    required this.sort,
    required this.compact,
    required this.shown,
    required this.total,
    required this.printingLabels,
    required this.selectionMode,
    required this.selectedCount,
    required this.allVisibleSelected,
    required this.onExitSelection,
    required this.onSelectAllVisible,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilter,
    required this.onSort,
    required this.onToggleDensity,
    required this.onMenu,
  });

  final ItemKind kind;
  final TextEditingController searchController;
  final String query;
  final _StockFilter filter;
  final _InventorySort sort;
  final bool compact;
  final int shown;
  final int total;
  final bool printingLabels;
  final bool selectionMode;
  final int selectedCount;
  final bool allVisibleSelected;
  final VoidCallback onExitSelection;
  final VoidCallback onSelectAllVisible;
  final VoidCallback onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_StockFilter> onFilter;
  final ValueChanged<_InventorySort> onSort;
  final VoidCallback onToggleDensity;
  final ValueChanged<_ShelfMenu> onMenu;

  @override
  Widget build(BuildContext context) {
    final chemical = kind == ItemKind.chemical;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectionMode)
          Row(
            key: const Key('selection-bar'),
            children: [
              IconButton(
                key: const Key('selection-close'),
                tooltip: 'Leave selection',
                onPressed: onExitSelection,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    fontFamily: 'ArchitectsDaughter',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('selection-select-all'),
                onPressed: onSelectAllVisible,
                icon: Icon(
                  allVisibleSelected
                      ? Icons.remove_done
                      : Icons.done_all,
                  size: 18,
                ),
                label: Text(
                  allVisibleSelected ? 'clear shown' : 'select shown',
                ),
              ),
            ],
          )
        else
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                onChanged: (_) => onSearchChanged(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: chemical
                      ? 'search by name, formula, note…'
                      : 'search by name, category, note…',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              key: const Key('inventory-density-toggle'),
              tooltip: compact ? 'Show detailed cards' : 'Show compact rows',
              onPressed: onToggleDensity,
              icon: Icon(
                compact ? Icons.view_agenda_outlined : Icons.view_list_outlined,
              ),
            ),
            PopupMenuButton<_ShelfMenu>(
              tooltip: 'Shelf actions',
              onSelected: onMenu,
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ShelfMenu.select,
                  enabled: total > 0,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.checklist),
                    title: Text('select items…'),
                  ),
                ),
                if (chemical) ...[
                  const PopupMenuItem(
                    value: _ShelfMenu.batchConsume,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.playlist_add_check),
                      title: Text('batch consume (multiple)'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ShelfMenu.printLabels,
                    enabled: !printingLabels && total > 0,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.qr_code_2),
                      title: Text(
                        printingLabels
                            ? 'preparing labels…'
                            : 'print QR labels (40 per A4)',
                      ),
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: _ShelfMenu.settings,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('settings'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 2,
          children: [
            NotebookFilterWord(
              label: 'all',
              selected: filter == _StockFilter.all,
              onTap: () => onFilter(_StockFilter.all),
              fontSize: 20,
            ),
            NotebookFilterWord(
              label: 'low',
              selected: filter == _StockFilter.low,
              onTap: () => onFilter(_StockFilter.low),
              fontSize: 20,
            ),
            NotebookFilterWord(
              label: 'critical',
              selected: filter == _StockFilter.critical,
              onTap: () => onFilter(_StockFilter.critical),
              fontSize: 20,
            ),
            PopupMenuButton<_InventorySort>(
              tooltip: 'Sort shelf',
              initialValue: sort,
              onSelected: onSort,
              itemBuilder: (context) => [
                for (final value in _InventorySort.values)
                  CheckedPopupMenuItem(
                    value: value,
                    checked: value == sort,
                    child: Text('sort by ${value.name}'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort, size: 17, color: context.mutedInkColor),
                    const SizedBox(width: 4),
                    Text(
                      'sort: ${sort.name}',
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontFamily: 'Caveat',
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: context.mutedInkColor,
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '$shown of $total',
              style: TextStyle(color: context.mutedInkColor, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

/// Vertical A–Z strip (UX-02). Letters without a matching item are visibly
/// disabled and inert; dragging along the strip previews the letter.
class AlphabetIndex extends StatefulWidget {
  const AlphabetIndex({
    required this.available,
    required this.onSelected,
    super.key,
  });

  final Set<String> available;
  final ValueChanged<String> onSelected;

  @override
  State<AlphabetIndex> createState() => _AlphabetIndexState();
}

class _AlphabetIndexState extends State<AlphabetIndex> {
  String? _active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final letters = alphabetIndexLetters;
        final slot = math.min(
          18.0,
          math.max(9.0, constraints.maxHeight / letters.length),
        );
        final fontSize = math.min(11.5, slot * .74);
        final stripHeight = slot * letters.length;
        final stripTop = math.max(
          0.0,
          (constraints.maxHeight - stripHeight) / 2,
        );
        final activeIndex = _active == null ? -1 : letters.indexOf(_active!);
        return SizedBox(
          width: 78,
          child: Stack(
            children: [
              Positioned(
                right: 4,
                top: stripTop,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTapDown: (details) => _select(details.localPosition, slot),
                  onTapUp: (_) => _clear(),
                  onTapCancel: _clear,
                  onVerticalDragStart: (details) =>
                      _select(details.localPosition, slot),
                  onVerticalDragUpdate: (details) =>
                      _select(details.localPosition, slot),
                  onVerticalDragEnd: (_) => _clear(),
                  onVerticalDragCancel: _clear,
                  child: Container(
                    width: 22,
                    decoration: BoxDecoration(
                      color: context.cardColor.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: context.ruledColor, width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final letter in letters)
                          Semantics(
                            button: true,
                            enabled: widget.available.contains(letter),
                            label: 'jump to $letter',
                            onTap: widget.available.contains(letter)
                                ? () => widget.onSelected(letter)
                                : null,
                            child: SizedBox(
                              height: slot,
                              width: 22,
                              child: Center(
                                child: Text(
                                  letter,
                                  key: Key('alpha-$letter'),
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    color: widget.available.contains(letter)
                                        ? (letter == _active
                                              ? context.marginRedColor
                                              : context.inkColor)
                                        : context.mutedInkColor.withValues(
                                            alpha: .32,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (activeIndex >= 0 && widget.available.contains(_active))
                Positioned(
                  right: 32,
                  top: (stripTop + activeIndex * slot + slot / 2 - 22).clamp(
                    0.0,
                    math.max(0.0, constraints.maxHeight - 44),
                  ),
                  child: IgnorePointer(
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.marginRedColor,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _active!,
                        style: TextStyle(
                          color: context.cardColor,
                          fontFamily: 'Caveat',
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _select(Offset local, double slot) {
    final raw = (local.dy / slot).floor();
    final index = math.max(0, math.min(alphabetIndexLetters.length - 1, raw));
    final letter = alphabetIndexLetters[index];
    if (letter == _active) return;
    setState(() => _active = letter);
    if (widget.available.contains(letter)) widget.onSelected(letter);
  }

  void _clear() {
    if (_active != null && mounted) setState(() => _active = null);
  }
}

class _InventoryView {
  const _InventoryView({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.searchText,
    required this.quantity,
    required this.unit,
    required this.threshold,
    required this.progress,
    required this.status,
  });

  factory _InventoryView.chemical(Chemical item) => _InventoryView(
    id: item.id,
    name: item.name,
    subtitle: item.formula.isEmpty ? 'no formula noted' : item.formula,
    searchText: '${item.name} ${item.formula} ${item.notes}',
    quantity: item.quantity,
    unit: item.unit,
    threshold: item.lowStockThreshold,
    progress: item.stockProgress,
    status: item.stockState,
  );

  factory _InventoryView.apparatus(Apparatus item) => _InventoryView(
    id: item.id,
    name: item.name,
    subtitle: item.category,
    searchText: '${item.name} ${item.category} ${item.notes}',
    quantity: item.quantity,
    unit: 'pcs',
    threshold: item.lowStockThreshold,
    progress: item.stockProgress,
    status: item.stockState,
  );

  final String id;
  final String name;
  final String subtitle;
  final String searchText;
  final double quantity;
  final String unit;
  final double threshold;
  final double progress;
  final StockState status;

  String get letter => indexLetterFor(name);
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.index,
    required this.tape,
    required this.kind,
    required this.onTap,
    required this.onConsume,
    required this.onRestock,
    this.selecting = false,
    this.selected = false,
    this.onLongPress,
  });

  final _InventoryView item;
  final int index;
  final NotebookTape tape;
  final ItemKind kind;
  final VoidCallback onTap;
  final VoidCallback onConsume;
  final VoidCallback onRestock;
  final bool selecting;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final flagged = item.status != StockState.healthy;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (flagged)
          Positioned(
            left: -43,
            top: 10,
            width: 38,
            child: MarginNote(
              item.status == StockState.empty ? 'empty!' : 'order!',
            ),
          ),
        Dismissible(
          key: ValueKey('${kind.name}-${item.id}'),
          direction: selecting
              ? DismissDirection.none
              : DismissDirection.horizontal,
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
            color: context.healthyColor,
            icon: Icons.add,
            text: 'restock',
          ),
          secondaryBackground: _SwipeBackground(
            alignment: Alignment.centerRight,
            color: kind == ItemKind.chemical
                ? context.lowColor
                : context.marginRedColor,
            icon: kind == ItemKind.chemical
                ? Icons.remove
                : Icons.report_problem_outlined,
            text: kind == ItemKind.chemical ? 'use' : 'damage',
          ),
          child: Hero(
            tag: '${kind.name}-${item.id}',
            child: NotebookCard(
              onTap: onTap,
              onLongPress: onLongPress,
              tape: tape,
              accent: selected ? context.inkColor : null,
              paperclip: item.status == StockState.empty,
              alternate: index.isOdd,
              rotation: index.isEven ? -.008 : .009,
              padding: const EdgeInsets.fromLTRB(15, 17, 15, 12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (selecting)
                        Padding(
                          padding: const EdgeInsets.only(right: 10, top: 2),
                          child: _SelectionMark(
                            selected: selected,
                            key: Key('select-mark-${item.id}'),
                          ),
                        ),
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
                                fontSize: 21,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.mutedInkColor,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedQuantity(
                            item.quantity,
                            suffix: ' ${item.unit}',
                            style: const TextStyle(
                              fontSize: 20,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            item.threshold > 0
                                ? 'min ${formatQuantity(item.threshold)} ${item.unit}'
                                : item.unit,
                            style: TextStyle(
                              color: context.mutedInkColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  StockBar(progress: item.progress, status: item.status),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stockCaption(item.status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: item.status == StockState.healthy
                                ? context.inkColor
                                : item.status == StockState.low
                                ? context.lowColor
                                : context.marginRedColor,
                            fontFamily: 'Caveat',
                            fontSize: 18,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            backgroundColor: item.status == StockState.empty
                                ? LabColors.highlighter.withValues(alpha: .72)
                                : null,
                          ),
                        ),
                      ),
                      _CardAction(
                        label: kind == ItemKind.chemical ? 'use' : 'damage',
                        color: context.marginRedColor,
                        onTap: selecting ? onTap : onConsume,
                      ),
                      const SizedBox(width: 10),
                      _CardAction(
                        label: '+ stock',
                        color: context.healthyColor,
                        onTap: selecting ? onTap : onRestock,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One-line shelf row for compact mode (UX-01). It keeps the quantity, the
/// stock status as text and color, the detail tap target, swipe gestures, and
/// direct use/damage and restock buttons.
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.item,
    required this.kind,
    required this.onTap,
    required this.onConsume,
    required this.onRestock,
    this.selecting = false,
    this.selected = false,
    this.onLongPress,
  });

  final _InventoryView item;
  final ItemKind kind;
  final VoidCallback onTap;
  final VoidCallback onConsume;
  final VoidCallback onRestock;
  final bool selecting;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final chemical = kind == ItemKind.chemical;
    final statusColor = switch (item.status) {
      StockState.healthy => context.healthyColor,
      StockState.low => context.lowColor,
      StockState.empty => context.marginRedColor,
    };
    final statusText = switch (item.status) {
      StockState.healthy => 'in stock',
      StockState.low => 'low',
      StockState.empty => 'empty',
    };
    return Dismissible(
      key: ValueKey('${kind.name}-${item.id}'),
      direction: selecting
          ? DismissDirection.none
          : DismissDirection.horizontal,
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
        color: context.healthyColor,
        icon: Icons.add,
        text: 'restock',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: chemical ? context.lowColor : context.marginRedColor,
        icon: chemical ? Icons.remove : Icons.report_problem_outlined,
        text: chemical ? 'use' : 'damage',
      ),
      child: Material(
        color: selected
            ? context.inkColor.withValues(alpha: .06)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
            child: Row(
              children: [
                if (selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _SelectionMark(
                      selected: selected,
                      key: Key('select-mark-${item.id}'),
                    ),
                  )
                else
                Semantics(
                  label: statusText,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: item.status == StockState.healthy
                          ? statusColor.withValues(alpha: .35)
                          : statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: statusColor, width: 1.6),
                    ),
                  ),
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
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.mutedInkColor,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedQuantity(
                      item.quantity,
                      suffix: ' ${item.unit}',
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: item.status == StockState.healthy
                            ? context.mutedInkColor
                            : statusColor,
                        fontFamily: 'Caveat',
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 2),
                if (!selecting) ...[
                  IconButton(
                    tooltip: chemical ? 'Use' : 'Report damage',
                    onPressed: onConsume,
                    visualDensity: VisualDensity.compact,
                    iconSize: 21,
                    color: context.marginRedColor,
                    icon: Icon(
                      chemical
                          ? Icons.remove_circle_outline
                          : Icons.report_problem_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Restock',
                    onPressed: onRestock,
                    visualDensity: VisualDensity.compact,
                    iconSize: 21,
                    color: context.healthyColor,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ] else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hand-drawn style check circle used while selecting items.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: selected ? 'selected' : 'not selected',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: selected ? context.inkColor : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: context.inkColor, width: 1.8),
        ),
        child: selected
            ? Icon(Icons.check, size: 16, color: context.paperColor)
            : null,
      ),
    );
  }
}

/// Bottom bar with the batch actions for the current selection.
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.kind,
    required this.count,
    required this.busy,
    required this.onAction,
  });

  final ItemKind kind;
  final int count;
  final bool busy;
  final ValueChanged<SelectionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !busy;
    return Material(
      key: const Key('selection-actions'),
      color: context.cardColor,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: _SelectionButton(
                  key: const Key('selection-restock'),
                  icon: Icons.add_circle_outline,
                  label: 'restock',
                  onPressed: enabled
                      ? () => onAction(SelectionAction.restock)
                      : null,
                ),
              ),
              Expanded(
                child: _SelectionButton(
                  key: const Key('selection-threshold'),
                  icon: Icons.tune,
                  label: 'threshold',
                  onPressed: enabled
                      ? () => onAction(SelectionAction.threshold)
                      : null,
                ),
              ),
              if (kind == ItemKind.chemical)
                Expanded(
                  child: _SelectionButton(
                    key: const Key('selection-labels'),
                    icon: Icons.qr_code_2,
                    label: busy ? 'preparing…' : 'labels',
                    onPressed: enabled
                        ? () => onAction(SelectionAction.labels)
                        : null,
                  ),
                ),
              Expanded(
                child: _SelectionButton(
                  key: const Key('selection-delete'),
                  icon: Icons.delete_outline,
                  label: 'delete',
                  color: context.marginRedColor,
                  onPressed: enabled
                      ? () => onAction(SelectionAction.delete)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionButton extends StatelessWidget {
  const _SelectionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? context.inkColor,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'Caveat',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
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
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft
            ? [
                Icon(icon, color: color),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ]
            : [
                Text(
                  text,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Icon(icon, color: color),
              ],
      ),
    );
  }
}

class _AddDoodle extends StatelessWidget {
  const _AddDoodle({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: context.cardColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.inkColor, width: 2.3),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '+',
                  style: TextStyle(
                    fontFamily: 'Caveat',
                    fontSize: 36,
                    height: .9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: context.mutedInkColor,
                  fontFamily: 'Caveat',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
