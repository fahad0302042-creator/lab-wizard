import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/models.dart';

/// Corrects or removes one entry from the history.
///
/// This exists because memory is not a database: someone remembers on
/// Thursday that Tuesday's 500 mL was really 50 mL, and the only honest fix is
/// to edit that entry — not to log a compensating second one nobody can read.
Future<void> showLogSheet(
  BuildContext context, {
  required ConsumptionLog log,
  required String itemName,
  required String unit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LogSheet(log: log, itemName: itemName, unit: unit),
  );
}

class _LogSheet extends ConsumerStatefulWidget {
  const _LogSheet({
    required this.log,
    required this.itemName,
    required this.unit,
  });

  final ConsumptionLog log;
  final String itemName;
  final String unit;

  @override
  ConsumerState<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<_LogSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: formatQuantity(widget.log.amount),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.log.note,
  );
  late InventoryAction _action = widget.log.action;
  late DateTime _date = widget.log.loggedAt;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_amount.text.trim());

  String? get _error {
    final value = _parsed;
    if (value == null || !value.isFinite || value <= 0) {
      return 'Enter an amount above zero';
    }
    if (widget.log.itemType == ItemKind.apparatus &&
        value != value.roundToDouble()) return 'Enter a whole number';
    return null;
  }

  bool get _changed =>
      _action != widget.log.action ||
      _parsed != widget.log.amount ||
      _note.text.trim() != widget.log.note ||
      !DateUtils.isSameDay(_date, widget.log.loggedAt);

  Future<void> _save() async {
    if (_error != null || _busy) return;
    final inventory = ref.read(inventoryProvider);
    final items = widget.log.itemType == ItemKind.chemical
        ? inventory.chemicals.map((e) => (e.id, e.quantity))
        : inventory.apparatus.map((e) => (e.id, e.quantity));
    final matches = items.where((item) => item.$1 == widget.log.itemId);
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item is no longer on the shelf.')),
      );
      return;
    }
    final current = matches.first.$2;
    final after = quantityAfterCorrection(
      currentQuantity: current,
      oldAction: widget.log.action,
      oldAmount: widget.log.amount,
      newAction: _action,
      newAmount: _parsed!,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm correction'),
        content: Text(
          'Change ${widget.log.action.name} ${formatQuantity(widget.log.amount)} '
          '${widget.unit} to ${_action.name} ${formatQuantity(_parsed!)} '
          '${widget.unit}.\n\n'
          'Estimated shelf balance: ${formatQuantity(current)} → '
          '${formatQuantity(after)} ${widget.unit}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save correction'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .correctAction(
            log: widget.log,
            action: _action,
            amount: _parsed!,
            note: _note.text,
            loggedAt: _date,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry corrected')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this entry?'),
        content: Text(
          widget.log.action == InventoryAction.restock
              ? 'The entry will be removed and its added amount will be '
                    'taken off the shelf balance.'
              : 'The entry will be removed and its amount will be put '
                    'back on the shelf balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(inventoryProvider.notifier).undoAction(widget.log);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry removed')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'What date was it really?',
    );
    if (picked != null && mounted) setState(() => _date = picked);
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
              'Fix this entry',
              style: TextStyle(
                fontFamily: 'Caveat',
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w700,
                color: lab.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(widget.itemName, style: context.itemName),
            const SizedBox(height: 16),
            SegmentedButton<InventoryAction>(
              segments: [
                if (widget.log.itemType == ItemKind.chemical ||
                    _action == InventoryAction.consume)
                  const ButtonSegment(
                    value: InventoryAction.consume,
                    label: Text('Used'),
                  ),
                const ButtonSegment(
                  value: InventoryAction.restock,
                  label: Text('Added'),
                ),
                if (widget.log.itemType == ItemKind.apparatus ||
                    _action == InventoryAction.breakage)
                  const ButtonSegment(
                    value: InventoryAction.breakage,
                    label: Text('Broken'),
                  ),
              ],
              selected: {_action},
              onSelectionChanged: _busy
                  ? null
                  : (value) => setState(() => _action = value.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              enabled: !_busy,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              style: context.figure.copyWith(fontSize: 22),
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: widget.unit,
                errorText: _amount.text.isEmpty ? null : _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              onChanged: (_) => setState(() {}),
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined, size: 17),
                  label: Text(
                    DateFormat('d MMM yyyy').format(_date),
                    style: const TextStyle(fontFamily: 'Caveat', fontSize: 18),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: lab.berry),
                  child: const Text('Remove'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _busy || _error != null || !_changed
                      ? null
                      : _save,
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
