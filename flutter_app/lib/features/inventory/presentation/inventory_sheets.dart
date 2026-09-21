import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
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

Future<void> showEditItemSheet(
  BuildContext context,
  WidgetRef _, {
  required ItemKind kind,
  required String itemId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SheetFrame(
      child: _EditItemForm(kind: kind, itemId: itemId),
    ),
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

Future<void> showBatchConsumeSheet(BuildContext context, WidgetRef _) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        const _SheetFrame(maxHeightFactor: .92, child: _BatchConsumeForm()),
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
  bool _dirty = false;

  static const _units = ['mL', 'g', 'mg', 'L', 'kg', 'drops', 'pcs'];
  static const _categories = [
    'glassware',
    'balances',
    'heating',
    'measurement',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _name,
      _subtitle,
      _quantity,
      _threshold,
      _notes,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

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
    return _UnsavedChangesGuard(
      dirty: _dirty,
      busy: _saving,
      onDiscard: () => _dirty = false,
      child: Form(
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
                onChanged: (value) => setState(() {
                  _category = value!;
                  _dirty = true;
                }),
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
                      onChanged: (value) => setState(() {
                        _unit = value!;
                        _dirty = true;
                      }),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _threshold,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
      _dirty = false;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${_name.text.trim()} added to the shelf')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      setState(() => _saving = false);
    }
  }
}

class _EditItemForm extends ConsumerStatefulWidget {
  const _EditItemForm({required this.kind, required this.itemId});

  final ItemKind kind;
  final String itemId;

  @override
  ConsumerState<_EditItemForm> createState() => _EditItemFormState();
}

class _EditItemFormState extends ConsumerState<_EditItemForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _subtitle;
  late final TextEditingController _threshold;
  late final TextEditingController _notes;
  late String _unit;
  late String _category;
  bool _saving = false;
  bool _dirty = false;

  static const _units = ['mL', 'g', 'mg', 'L', 'kg', 'drops', 'pcs'];
  static const _categories = [
    'glassware',
    'balances',
    'heating',
    'measurement',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final state = ref.read(inventoryProvider);
    final chemical = widget.kind == ItemKind.chemical
        ? state.chemicals.where((item) => item.id == widget.itemId).firstOrNull
        : null;
    final apparatus = widget.kind == ItemKind.apparatus
        ? state.apparatus.where((item) => item.id == widget.itemId).firstOrNull
        : null;
    _name = TextEditingController(
      text: chemical?.name ?? apparatus?.name ?? '',
    );
    _subtitle = TextEditingController(text: chemical?.formula ?? '');
    _threshold = TextEditingController(
      text: formatQuantity(
        chemical?.lowStockThreshold ?? apparatus?.lowStockThreshold ?? 0,
      ),
    );
    _notes = TextEditingController(
      text: chemical?.notes ?? apparatus?.notes ?? '',
    );
    _unit = chemical?.unit ?? 'mL';
    _category = apparatus?.category ?? 'other';
    if (!_units.contains(_unit)) _unit = 'pcs';
    if (!_categories.contains(_category)) _category = 'other';
    for (final controller in [_name, _subtitle, _threshold, _notes]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _threshold.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chemical = widget.kind == ItemKind.chemical;
    return _UnsavedChangesGuard(
      dirty: _dirty,
      busy: _saving,
      onDiscard: () => _dirty = false,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(chemical ? 'edit chemical' : 'edit apparatus'),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: chemical ? 'Chemical name' : 'Apparatus name',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            if (chemical)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _subtitle,
                      decoration: const InputDecoration(labelText: 'Formula'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
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
                      onChanged: (value) => setState(() {
                        _unit = value!;
                        _dirty = true;
                      }),
                    ),
                  ),
                ],
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
                onChanged: (value) => setState(() {
                  _category = value!;
                  _dirty = true;
                }),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _threshold,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Low-stock level',
                helperText: 'The shelf flags the item at or below this amount.',
              ),
              validator: (value) {
                final number = double.tryParse((value ?? '').trim());
                return number == null || number < 0 ? 'Enter 0 or more' : null;
              },
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
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
              label: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .updateItem(
            type: widget.kind,
            id: widget.itemId,
            changes: widget.kind == ItemKind.chemical
                ? {
                    'name': _name.text.trim(),
                    'formula': _subtitle.text.trim(),
                    'unit': _unit,
                    'low_stock_threshold': double.parse(_threshold.text.trim()),
                    'notes': _notes.text.trim(),
                  }
                : {
                    'name': _name.text.trim(),
                    'category': _category,
                    'low_stock_threshold': double.parse(_threshold.text.trim()),
                    'notes': _notes.text.trim(),
                  },
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      _dirty = false;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Item updated')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }
}

class _BatchConsumeForm extends ConsumerStatefulWidget {
  const _BatchConsumeForm();

  @override
  ConsumerState<_BatchConsumeForm> createState() => _BatchConsumeFormState();
}

class _BatchConsumeFormState extends ConsumerState<_BatchConsumeForm> {
  final _selected = <String>{};
  final _amounts = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chemicals =
        ref
            .watch(inventoryProvider)
            .chemicals
            .where((item) => item.quantity > 0)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading('batch consume'),
        Text(
          'Select several reagents and record them together. Each change keeps its own audit entry.',
          style: TextStyle(color: context.mutedInkColor),
        ),
        const SizedBox(height: 12),
        if (chemicals.isEmpty)
          const EmptyNotebookState(
            icon: Icons.science_outlined,
            title: 'nothing available',
            message: 'Restock a chemical before recording consumption.',
          )
        else
          ...chemicals.map((chemical) {
            final selected = _selected.contains(chemical.id);
            final controller = _amounts.putIfAbsent(
              chemical.id,
              () => TextEditingController(text: '1'),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: NotebookCard(
                tape: selected ? NotebookTape.yellow : NotebookTape.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() {
                                  if (value ?? false) {
                                    _selected.add(chemical.id);
                                  } else {
                                    _selected.remove(chemical.id);
                                  }
                                }),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chemical.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'ArchitectsDaughter',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${formatQuantity(chemical.quantity)} ${chemical.unit} available',
                                style: TextStyle(
                                  color: context.mutedInkColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          SizedBox(
                            width: 86,
                            child: TextField(
                              controller: controller,
                              enabled: !_saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.end,
                              decoration: InputDecoration(
                                suffixText: chemical.unit,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (selected &&
                        (double.tryParse(controller.text) ?? 0) >
                            chemical.quantity)
                      Text(
                        'Amount cannot exceed available stock.',
                        style: TextStyle(
                          color: context.marginRedColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _selected.isEmpty || _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check),
          label: Text(
            _saving
                ? 'Recording…'
                : 'Record ${_selected.length} usage ${_selected.length == 1 ? 'entry' : 'entries'}',
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final state = ref.read(inventoryProvider);
    final selectedItems = state.chemicals
        .where((item) => _selected.contains(item.id))
        .toList();
    for (final item in selectedItems) {
      final amount = double.tryParse(_amounts[item.id]?.text.trim() ?? '');
      if (amount == null || amount <= 0 || amount > item.quantity) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check the amount for ${item.name}.')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      for (final item in selectedItems) {
        await ref
            .read(inventoryProvider.notifier)
            .applyAction(
              itemId: item.id,
              itemType: ItemKind.chemical,
              action: InventoryAction.consume,
              amount: double.parse(_amounts[item.id]!.text.trim()),
              note: 'Batch consume',
              date: DateTime.now(),
            );
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${selectedItems.length} usage entries recorded'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
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
    final unit = widget.kind == ItemKind.chemical
        ? state.chemicals
                  .where((item) => item.id == widget.itemId)
                  .map((item) => item.unit)
                  .firstOrNull ??
              ''
        : 'pcs';
    final enteredAmount = double.tryParse(_amount.text.trim()) ?? 0;
    final double nextQuantity = widget.action == InventoryAction.restock
        ? (current ?? 0) + enteredAmount
        : ((current ?? 0) - enteredAmount).clamp(0, double.infinity).toDouble();
    final color = switch (widget.action) {
      InventoryAction.restock => context.healthyColor,
      InventoryAction.consume => context.lowColor,
      InventoryAction.breakage => context.marginRedColor,
    };
    final actionLabel = switch (widget.action) {
      InventoryAction.restock => 'restock',
      InventoryAction.consume => 'consume',
      InventoryAction.breakage => 'report damage',
    };

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading(actionLabel),
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
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Amount', suffixText: unit),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              for (final amount in <double>[1, 5, 10, 25])
                ActionChip(
                  label: Text(formatQuantity(amount)),
                  onPressed: () {
                    _amount.text = formatQuantity(amount);
                    setState(() {});
                  },
                ),
              if (widget.action != InventoryAction.restock &&
                  (current ?? 0) > 0)
                ActionChip(
                  label: const Text('all'),
                  onPressed: () {
                    _amount.text = formatQuantity(current ?? 0);
                    setState(() {});
                  },
                ),
            ],
          ),
          if (enteredAmount > 0) ...[
            const SizedBox(height: 12),
            NotebookCard(
              tape: NotebookTape.yellow,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: _QuantityPreview(
                      label: 'before',
                      value: current ?? 0,
                      unit: unit,
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: context.mutedInkColor),
                  Expanded(
                    child: _QuantityPreview(
                      label: 'after',
                      value: nextQuantity,
                      unit: unit,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            label: Text(_saving ? 'Saving…' : 'Confirm $actionLabel'),
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
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
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
            PageHeading(
              name,
              trailing: IconButton(
                tooltip: 'Edit item',
                onPressed: () =>
                    showEditItemSheet(context, ref, kind: kind, itemId: itemId),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
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
                      kind == ItemKind.chemical ? 'Consume' : 'Report damage',
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
            if ((chemical?.qrCode.isNotEmpty ?? false) ||
                apparatus != null) ...[
              const SizedBox(height: 24),
              const PageHeading('QR label', trailing: SizedBox.shrink()),
              Text(
                'Print or screenshot this label for instant scanning.',
                style: TextStyle(color: context.mutedInkColor, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Center(
                child: NotebookCard(
                  tape: NotebookTape.yellow,
                  padding: const EdgeInsets.all(12),
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: QrImageView(
                        data: chemical != null
                            ? 'labwizard:chemical:${chemical.qrCode}'
                            : 'labwizard:apparatus:$itemId',
                        size: 152,
                        backgroundColor: Colors.white,
                      ),
                    ),
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
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }
}

class _UnsavedChangesGuard extends StatelessWidget {
  const _UnsavedChangesGuard({
    required this.dirty,
    required this.busy,
    required this.onDiscard,
    required this.child,
  });

  final bool dirty;
  final bool busy;
  final VoidCallback onDiscard;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || busy) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text(
              'Your edits have not been saved to the notebook yet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          onDiscard();
          Navigator.pop(context);
        }
      },
      child: child,
    );
  }
}

class _QuantityPreview extends StatelessWidget {
  const _QuantityPreview({
    required this.label,
    required this.value,
    required this.unit,
    this.alignEnd = false,
  });

  final String label;
  final double value;
  final String unit;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.mutedInkColor,
            fontFamily: 'Caveat',
            fontSize: 15,
          ),
        ),
        Text(
          '${formatQuantity(value)} $unit',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

String _friendlyError(Object error) => friendlyErrorMessage(error);

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
