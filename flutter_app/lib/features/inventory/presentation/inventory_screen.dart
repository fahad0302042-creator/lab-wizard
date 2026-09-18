import 'package:flutter/material.dart';
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
import 'inventory_sheets.dart';

enum _StockFilter { all, low, critical }

enum _InventorySort { name, quantity, status }

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({required this.kind, super.key});

  final ItemKind kind;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  _StockFilter _filter = _StockFilter.all;
  _InventorySort _sort = _InventorySort.name;
  bool _printingLabels = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final query = _searchController.text.trim().toLowerCase();
    final allItems = widget.kind == ItemKind.chemical
        ? state.chemicals
              .map(
                (item) => _InventoryView(
                  id: item.id,
                  name: item.name,
                  subtitle: item.formula.isEmpty
                      ? 'no formula noted'
                      : item.formula,
                  searchText: '${item.name} ${item.formula} ${item.notes}',
                  quantity: item.quantity,
                  unit: item.unit,
                  threshold: item.lowStockThreshold,
                  progress: item.stockProgress,
                  status: item.stockState,
                ),
              )
              .toList()
        : state.apparatus
              .map(
                (item) => _InventoryView(
                  id: item.id,
                  name: item.name,
                  subtitle: item.category,
                  searchText: '${item.name} ${item.category} ${item.notes}',
                  quantity: item.quantity,
                  unit: 'pcs',
                  threshold: item.lowStockThreshold,
                  progress: item.stockProgress,
                  status: item.stockState,
                ),
              )
              .toList();

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

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'add-${widget.kind.name}',
        tooltip: widget.kind == ItemKind.chemical
            ? 'Add chemical'
            : 'Add apparatus',
        onPressed: () => showAddItemSheet(context, ref, widget.kind),
        elevation: 2,
        backgroundColor: context.cardColor,
        foregroundColor: context.inkColor,
        shape: CircleBorder(
          side: BorderSide(color: context.inkColor, width: 2),
        ),
        child: const Icon(Icons.add, size: 27),
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(inventoryProvider.notifier).refresh,
        child: CustomScrollView(
          key: PageStorageKey('inventory-${widget.kind.name}'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(54, 18, 20, 8),
              sliver: SliverList.list(
                children: [
                  PageHeading(
                    widget.kind == ItemKind.chemical
                        ? 'chemicals shelf'
                        : 'apparatus shelf',
                    trailing: IconButton(
                      tooltip: 'Settings',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: widget.kind == ItemKind.chemical
                          ? 'search by name, formula, note…'
                          : 'search by name, category, note…',
                      prefixIcon: const Icon(Icons.search, size: 22),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      NotebookFilterWord(
                        label: 'all',
                        selected: _filter == _StockFilter.all,
                        onTap: () => setState(() => _filter = _StockFilter.all),
                      ),
                      const SizedBox(width: 16),
                      NotebookFilterWord(
                        label: 'low',
                        selected: _filter == _StockFilter.low,
                        onTap: () => setState(() => _filter = _StockFilter.low),
                      ),
                      const SizedBox(width: 16),
                      NotebookFilterWord(
                        label: 'critical',
                        selected: _filter == _StockFilter.critical,
                        onTap: () =>
                            setState(() => _filter = _StockFilter.critical),
                      ),
                      const Spacer(),
                      Text(
                        '${items.length} of ${allItems.length}',
                        style: TextStyle(color: context.mutedInkColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      Text(
                        'sort:',
                        style: TextStyle(
                          color: context.mutedInkColor,
                          fontSize: 12,
                        ),
                      ),
                      for (final sort in _InventorySort.values)
                        NotebookFilterWord(
                          label: sort.name,
                          selected: _sort == sort,
                          onTap: () => setState(() => _sort = sort),
                          fontSize: 20,
                        ),
                    ],
                  ),
                  if (widget.kind == ItemKind.chemical &&
                      state.chemicals.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 13,
                      runSpacing: 2,
                      children: [
                        TextButton(
                          onPressed: () => showBatchConsumeSheet(context, ref),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('batch consume (multiple)'),
                        ),
                        TextButton.icon(
                          onPressed: _printingLabels
                              ? null
                              : () => _printQrLabels(state.chemicals),
                          style: TextButton.styleFrom(
                            foregroundColor: context.mutedInkColor,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: _printingLabels
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.qr_code_2, size: 18),
                          label: Text(
                            _printingLabels
                                ? 'preparing labels…'
                                : 'print QR labels (40 per A4)',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (state.loading && allItems.isEmpty)
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
                  title: query.isEmpty ? 'empty shelf' : 'nothing matches',
                  message: query.isEmpty
                      ? 'Tap the circled + to add your first item.'
                      : 'Try another search, filter, or sort.',
                  action: CircledNotebookButton(
                    label: widget.kind == ItemKind.chemical
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
                padding: const EdgeInsets.fromLTRB(54, 6, 20, 22),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 18),
                  itemBuilder: (context, index) => StaggerIn(
                    index: index,
                    child: _InventoryCard(
                      item: items[index],
                      index: index,
                      tape: _tapes[index % _tapes.length],
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(54, 4, 20, 108),
                  child: _AddDoodle(
                    label: widget.kind == ItemKind.chemical
                        ? '~ add new reagent ~'
                        : '~ add new apparatus ~',
                    onTap: () => showAddItemSheet(context, ref, widget.kind),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  Future<void> _printQrLabels(List<Chemical> chemicals) async {
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

  final String id;
  final String name;
  final String subtitle;
  final String searchText;
  final double quantity;
  final String unit;
  final double threshold;
  final double progress;
  final StockState status;
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
  });

  final _InventoryView item;
  final int index;
  final NotebookTape tape;
  final ItemKind kind;
  final VoidCallback onTap;
  final VoidCallback onConsume;
  final VoidCallback onRestock;

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
              tape: tape,
              paperclip: item.status == StockState.empty,
              alternate: index.isOdd,
              rotation: index.isEven ? -.008 : .009,
              padding: const EdgeInsets.fromLTRB(15, 17, 15, 12),
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
                        color: kind == ItemKind.chemical
                            ? context.marginRedColor
                            : context.marginRedColor,
                        onTap: onConsume,
                      ),
                      const SizedBox(width: 10),
                      _CardAction(
                        label: '+ stock',
                        color: context.healthyColor,
                        onTap: onRestock,
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
