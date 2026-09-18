import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';

Future<void> showAddItemSheet(
  BuildContext context,
  WidgetRef _,
  ItemKind kind,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SheetFrame(child: _AddItemForm(kind: kind)),
  );
}

Future<void> showInventoryActionSheet(
  BuildContext context,
  WidgetRef _, {
  required ItemKind kind,
  required String itemId,
  required InventoryAction action,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SheetFrame(
      child: _ActionForm(kind: kind, itemId: itemId, action: action),
    ),
  );
}

Future<void> showItemDetailSheet(
  BuildContext context,
  WidgetRef _,
  ItemKind kind,
  String itemId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SheetFrame(
      maxHeightFactor: .9,
      child: _ItemDetail(kind: kind, itemId: itemId),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.maxHeightFactor = .94});

  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.paperColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AddItemForm extends ConsumerStatefulWidget {
  const _AddItemForm({required this.kind});

  final ItemKind kind;

  @override
  ConsumerState<_AddItemForm> createState() => _AddItemFormState();
}

class _AddItemFormState extends ConsumerState<_AddItemForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _subtitle = TextEditingController();
  final _quantity = TextEditingController();
  final _threshold = TextEditingController();
  final _notes = TextEditingController();
  String _unit = 'mL';
  String _category = 'glassware';
  bool _saving = false;

  static const _units = ['mL', 'g', 'mg', 'L', 'kg', 'drops', 'pcs'];
  static const _categories = [
    'glassware',
    'balances',
    'heating',
    'measurement',
    'other',
  ];

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _quantity.dispose();
    _threshold.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chemical = widget.kind == ItemKind.chemical;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading(chemical ? 'add chemical' : 'add apparatus'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: chemical ? 'Chemical name' : 'Apparatus name',
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          if (chemical)
            TextFormField(
              controller: _subtitle,
              decoration: const InputDecoration(
                labelText: 'Formula',
                hintText: 'e.g. HCl',
              ),
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
              onChanged: (value) => setState(() => _category = value!),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Starting quantity',
                  ),
                  validator: _nonNegativeNumber,
                ),
              ),
              if (chemical) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 105,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: _units
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _unit = value!),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _threshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Low-stock level',
              helperText: 'The item is flagged at or below this amount.',
            ),
            validator: _optionalNonNegativeNumber,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Cabinet, supplier, safety note…',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(_saving ? 'Saving…' : 'Add to shelf'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;

  String? _nonNegativeNumber(String? value) {
    final number = double.tryParse((value ?? '').trim());
    return number == null || number < 0 ? 'Enter 0 or more' : null;
  }

  String? _optionalNonNegativeNumber(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    return _nonNegativeNumber(value);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final quantity = double.parse(_quantity.text);
      final threshold = double.tryParse(_threshold.text) ?? 0;
      if (widget.kind == ItemKind.chemical) {
        await ref
            .read(inventoryProvider.notifier)
            .addChemical(
              name: _name.text,
              formula: _subtitle.text,
              unit: _unit,
              quantity: quantity,
              threshold: threshold,
              notes: _notes.text,
            );
      } else {
        await ref
            .read(inventoryProvider.notifier)
            .addApparatus(
              name: _name.text,
              category: _category,
              quantity: quantity,
              threshold: threshold,
              notes: _notes.text,
            );
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${_name.text.trim()} added to the shelf')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => _saving = false);
    }
  }
}

class _ActionForm extends ConsumerStatefulWidget {
  const _ActionForm({
    required this.kind,
    required this.itemId,
    required this.action,
  });

  final ItemKind kind;
  final String itemId;
  final InventoryAction action;

  @override
  ConsumerState<_ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends ConsumerState<_ActionForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final itemName = widget.kind == ItemKind.chemical
        ? state.chemicals
              .where((item) => item.id == widget.itemId)
              .map((item) => item.name)
              .firstOrNull
        : state.apparatus
              .where((item) => item.id == widget.itemId)
              .map((item) => item.name)
              .firstOrNull;
    final current = widget.kind == ItemKind.chemical
        ? state.chemicals
              .where((item) => item.id == widget.itemId)
              .map((item) => item.quantity)
              .firstOrNull
        : state.apparatus
              .where((item) => item.id == widget.itemId)
              .map((item) => item.quantity)
              .firstOrNull;
    final color = switch (widget.action) {
      InventoryAction.restock => LabColors.green,
      InventoryAction.consume => LabColors.amber,
      InventoryAction.breakage => LabColors.marginRed,
    };

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading(widget.action.name),
          Text(
            itemName ?? 'Item',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            '${formatQuantity(current ?? 0)} currently available',
            style: TextStyle(color: context.mutedInkColor),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
            validator: (value) {
              final number = double.tryParse((value ?? '').trim());
              if (number == null || number <= 0) {
                return 'Enter an amount greater than 0';
              }
              if (widget.action != InventoryAction.restock &&
                  current != null &&
                  number > current) {
                return 'Only ${formatQuantity(current)} available';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Optional context for the audit log',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('${_date.day}/${_date.month}/${_date.year}'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.action == InventoryAction.restock
                        ? Icons.add
                        : Icons.remove,
                  ),
            label: Text(_saving ? 'Saving…' : 'Confirm ${widget.action.name}'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _date,
    );
    if (result != null) setState(() => _date = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .applyAction(
            itemId: widget.itemId,
            itemType: widget.kind,
            action: widget.action,
            amount: double.parse(_amount.text),
            note: _note.text,
            date: _date,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.action.name} recorded')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _ItemDetail extends ConsumerWidget {
  const _ItemDetail({required this.kind, required this.itemId});

  final ItemKind kind;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inventoryProvider);
    final chemical = kind == ItemKind.chemical
        ? state.chemicals.where((item) => item.id == itemId).firstOrNull
        : null;
    final apparatus = kind == ItemKind.apparatus
        ? state.apparatus.where((item) => item.id == itemId).firstOrNull
        : null;
    if (chemical == null && apparatus == null) {
      return const EmptyNotebookState(
        icon: Icons.search_off,
        title: 'item not found',
        message: 'It may have been removed on another device.',
      );
    }
    final name = chemical?.name ?? apparatus!.name;
    final subtitle = chemical?.formula ?? apparatus!.category;
    final quantity = chemical?.quantity ?? apparatus!.quantity;
    final unit = chemical?.unit ?? 'pcs';
    final threshold =
        chemical?.lowStockThreshold ?? apparatus!.lowStockThreshold;
    final notes = chemical?.notes ?? apparatus!.notes;
    final status = chemical?.stockState ?? apparatus!.stockState;
    final progress = chemical?.stockProgress ?? apparatus!.stockProgress;
    final itemLogs = state.logs
        .where((log) => log.itemId == itemId)
        .take(8)
        .toList();

    return Hero(
      tag: '${kind.name}-$itemId',
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(name),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(color: context.mutedInkColor, fontSize: 17),
              ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedQuantity(
                    quantity,
                    suffix: ' $unit',
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                StatusBadge(status),
              ],
            ),
            const SizedBox(height: 12),
            StockBar(progress: progress, status: status),
            if (threshold > 0) ...[
              const SizedBox(height: 5),
              Text(
                'Low-stock level: ${formatQuantity(threshold)} $unit',
                style: TextStyle(color: context.mutedInkColor, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showInventoryActionSheet(
                      context,
                      ref,
                      kind: kind,
                      itemId: itemId,
                      action: kind == ItemKind.chemical
                          ? InventoryAction.consume
                          : InventoryAction.breakage,
                    ),
                    icon: Icon(
                      kind == ItemKind.chemical
                          ? Icons.remove
                          : Icons.broken_image_outlined,
                    ),
                    label: Text(
                      kind == ItemKind.chemical ? 'Consume' : 'Breakage',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showInventoryActionSheet(
                      context,
                      ref,
                      kind: kind,
                      itemId: itemId,
                      action: InventoryAction.restock,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Restock'),
                  ),
                ),
              ],
            ),
            if (chemical != null && chemical.qrCode.isNotEmpty) ...[
              const SizedBox(height: 24),
              const PageHeading('QR label', trailing: SizedBox.shrink()),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(14),
                  child: QrImageView(
                    data: 'labwizard:chemical:${chemical.qrCode}',
                    size: 152,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 24),
              const PageHeading('notes', trailing: SizedBox.shrink()),
              NotebookCard(child: Text(notes)),
            ],
            const SizedBox(height: 24),
            const PageHeading('history', trailing: SizedBox.shrink()),
            if (itemLogs.isEmpty)
              Text(
                'No activity yet.',
                style: TextStyle(color: context.mutedInkColor),
              )
            else
              ...itemLogs.map(
                (log) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(
                      log.action == InventoryAction.restock
                          ? Icons.add
                          : Icons.remove,
                    ),
                  ),
                  title: Text(
                    '${log.action.name} ${formatQuantity(log.amount)} $unit',
                  ),
                  subtitle: Text(
                    '${log.loggedAt.day}/${log.loggedAt.month}/${log.loggedAt.year}${log.note.isEmpty ? '' : ' · ${log.note}'}',
                  ),
                ),
              ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _delete(context, ref, name),
              style: TextButton.styleFrom(foregroundColor: LabColors.marginRed),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete item'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text(
          '$name and its history will be removed. This requires an internet connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(inventoryProvider.notifier).deleteItem(kind, itemId);
      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
