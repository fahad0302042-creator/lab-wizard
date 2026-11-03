import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shelf_row.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import 'action_sheet.dart';
import 'item_sheet.dart';

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
  Timer? _undoTimer;
  bool _searching = false;
  bool _printing = false;

  bool get _isChemical => widget.kind == ItemKind.chemical;

  @override
  void dispose() {
    _undoTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<ItemView> _items(InventoryState state) {
    final query = _search.text.trim().toLowerCase();
    final views = _isChemical
        ? state.chemicals.map(ItemView.fromChemical)
        : state.apparatus.map(ItemView.fromApparatus);
    final filtered = views.where((item) {
      if (query.isEmpty) return true;
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
                  total: items.length,
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
                  extra: _isChemical && items.isNotEmpty
                      ? _printLabelsButton(state)
                      : null,
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
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ShelfRowIn(
                        index: index,
                        child: ShelfRow(
                          item: item,
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

  Widget _printLabelsButton(InventoryState state) {
    return TextButton.icon(
      onPressed: _printing ? null : () => _printLabels(state.chemicals),
      icon: _printing
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.qr_code_2, size: 17),
      label: Text(_printing ? 'preparing…' : 'QR labels'),
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
                _setLimit(context, ref, item);
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

  Future<void> _setLimit(
    BuildContext context,
    WidgetRef ref,
    ItemView item,
  ) async {
    final controller = TextEditingController(
      text: item.threshold > 0 ? formatQuantity(item.threshold) : '',
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
              'I will flag ${item.name} once it drops below this. Leave it '
              'empty and the jar stays fine until it is empty.',
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
                suffixText: item.unit,
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
            type: widget.kind,
            id: item.id,
            changes: {'low_stock_threshold': saved},
          );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
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
      builder: (_) => const _MenuSheet(),
    );
  }

  /// A4 sheet, 40 labels per page: five across, eight down.
  Future<void> _printLabels(List<Chemical> chemicals) async {
    setState(() => _printing = true);
    try {
      final document = pw.Document(title: 'Lab Wizard QR labels');
      for (var offset = 0; offset < chemicals.length; offset += 40) {
        final pageItems = chemicals.skip(offset).take(40).toList();
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (_) => pw.Column(
              children: List.generate(
                8,
                (row) => pw.Expanded(
                  child: pw.Row(
                    children: List.generate(5, (column) {
                      final index = row * 5 + column;
                      return pw.Expanded(
                        child: index >= pageItems.length
                            ? pw.SizedBox()
                            : _label(pageItems[index]),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      await Printing.layoutPdf(
        name: 'Lab-Wizard-QR-Labels.pdf',
        onLayout: (_) => document.save(),
      );
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  pw.Widget _label(Chemical chemical) => pw.Container(
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

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.attention,
    required this.total,
    required this.searching,
    required this.search,
    required this.onSearchToggle,
    required this.onSearchChanged,
    required this.onMenu,
    this.extra,
  });

  final String title;
  final int attention;
  final int total;
  final bool searching;
  final TextEditingController search;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMenu;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMMM').format(DateTime.now()),
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
                  : '$attention ${attention == 1 ? 'jar needs' : 'jars need'} '
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
              _Stat(
                label: title == 'chemicals' ? 'Reagents' : 'Pieces',
                value: total,
              ),
              _Stat(label: 'To order', value: attention),
              _Stat(label: 'Showing', value: total, last: true),
            ],
          ),
          if (extra != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: extra),
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
  const _Stat({required this.value, required this.label, this.last = false});

  final int value;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(right: BorderSide(color: lab.hair)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CountUp(
              value: value.toDouble(),
              builder: (context, animated) => Text(
                formatQuantity(animated),
                style: TextStyle(
                  fontSize: 21,
                  height: 1.1,
                  letterSpacing: -.8,
                  fontWeight: FontWeight.w600,
                  color: lab.ink,
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
                            : '${formatQuantity(log!.amount)} '
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
                final wait = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Still uploading'),
                    content: Text(
                      '$pending change${pending == 1 ? '' : 's'} haven\'t '
                      'reached the server yet. They will be kept and uploaded '
                      'next time you sign in.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Stay signed in'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Sign out anyway'),
                      ),
                    ],
                  ),
                );
                if (wait != true) return;
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
