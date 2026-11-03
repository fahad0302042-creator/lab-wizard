import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';

/// Sets the level at which a shelf starts asking for attention.
///
/// This is the manual low-stock switch. The app deliberately stays quiet until
/// a level exists — "no level" means nobody has decided what low means — so for
/// a new item this sheet is the difference between a shelf that can warn and
/// one that never will. Setting it to zero switches the warning back off.
Future<void> showOrderLevelSheet(
  BuildContext context, {
  required ItemView item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderLevelSheet(item: item),
  );
}

class _OrderLevelSheet extends ConsumerStatefulWidget {
  const _OrderLevelSheet({required this.item});

  final ItemView item;

  @override
  ConsumerState<_OrderLevelSheet> createState() => _OrderLevelSheetState();
}

class _OrderLevelSheetState extends ConsumerState<_OrderLevelSheet> {
  late final TextEditingController _level = TextEditingController(
    text: widget.item.threshold > 0
        ? formatQuantity(widget.item.threshold)
        : '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _level.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_level.text.trim()) ?? 0;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .updateItem(
            type: widget.item.kind,
            id: widget.item.id,
            changes: {'low_stock_threshold': _value},
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _value > 0
                ? '${widget.item.name} will ask for attention below '
                      '${formatQuantity(_value)} ${widget.item.unit}'
                : '${widget.item.name} will not warn any more',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
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
      child: Container(
        decoration: BoxDecoration(
          color: lab.bone,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: lab.hair,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Order level',
              style: TextStyle(
                fontFamily: 'Caveat',
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w700,
                color: lab.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(widget.item.name, style: context.itemName),
            const SizedBox(height: 6),
            Text(
              'On the shelf now: ${formatQuantity(widget.item.quantity)} '
              '${widget.item.unit}. Below this level the row shows "order" and '
              'a low-stock alert can be sent. Leave it empty for no warning.',
              style: context.aside.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _level,
              autofocus: true,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              style: context.figure.copyWith(fontSize: 22),
              decoration: InputDecoration(
                labelText: 'Warn below',
                suffixText: widget.item.unit,
                hintText: 'no warning',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _level.text = ''),
                  child: const Text('No warning'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits the record itself: name, formula or category, unit, quantity and the
/// order level. Quantity is here on purpose — a physical count that disagrees
/// with the app is a fact about the bottle, not a consumption event.
Future<void> showEditItemSheet(
  BuildContext context, {
  required ItemView item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditItemSheet(item: item),
  );
}

class _EditItemSheet extends ConsumerStatefulWidget {
  const _EditItemSheet({required this.item});

  final ItemView item;

  @override
  ConsumerState<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends ConsumerState<_EditItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _subtitle = TextEditingController(text: widget.item.subtitle);
  late final _unit = TextEditingController(text: widget.item.unit);
  late final _quantity = TextEditingController(
    text: formatQuantity(widget.item.quantity),
  );
  late final _level = TextEditingController(
    text: widget.item.threshold > 0
        ? formatQuantity(widget.item.threshold)
        : '',
  );
  late final _notes = TextEditingController(text: widget.item.notes);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _unit.dispose();
    _quantity.dispose();
    _level.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A name is needed')),
      );
      return;
    }
    setState(() => _busy = true);
    final isChemical = widget.item.kind == ItemKind.chemical;
    try {
      await ref
          .read(inventoryProvider.notifier)
          .updateItem(
            type: widget.item.kind,
            id: widget.item.id,
            changes: {
              'name': _name.text.trim(),
              if (isChemical) 'formula': _subtitle.text.trim(),
              if (isChemical) 'unit': _unit.text.trim().isEmpty
                  ? 'mL'
                  : _unit.text.trim(),
              'quantity': double.tryParse(_quantity.text.trim()) ?? 0,
              'low_stock_threshold':
                  double.tryParse(_level.text.trim()) ?? 0,
              'notes': _notes.text.trim(),
              if (!isChemical && _subtitle.text.trim().isNotEmpty)
                'category': _subtitle.text.trim(),
            },
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final isChemical = widget.item.kind == ItemKind.chemical;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: lab.bone,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: lab.hair,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Edit item',
                style: TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: lab.ink,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subtitle,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: isChemical ? 'Formula' : 'Category',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantity,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'On the shelf now',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _unit,
                      enabled: !_busy && isChemical,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _level,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Order level (empty for no warning)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                enabled: !_busy,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
