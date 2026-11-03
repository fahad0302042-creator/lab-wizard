import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_jar.dart';
import '../../../core/widgets/jar_metrics.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';

/// Records use or restock for one item.
///
/// The amount is pre-filled with the amount most often logged for this item,
/// because a lab tends to use the same amount repeatedly — one tap usually does
/// it. Returns the log so the shelf can offer a real undo.
Future<ConsumptionLog?> showActionSheet(
  BuildContext context,
  WidgetRef ref, {
  required ItemView item,
  required InventoryAction action,
}) {
  return showModalBottomSheet<ConsumptionLog>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ActionSheet(item: item, action: action),
  );
}

class _ActionSheet extends ConsumerStatefulWidget {
  const _ActionSheet({required this.item, required this.action});

  final ItemView item;
  final InventoryAction action;

  @override
  ConsumerState<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends ConsumerState<_ActionSheet> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  late DateTime _date = DateTime.now();
  bool _saving = false;

  bool get _isUse => widget.action != InventoryAction.restock;

  double _suggestedAmount() {
    final logs = ref
        .read(inventoryProvider)
        .logs
        .where((log) => log.itemId == widget.item.id)
        .toList();
    if (logs.isEmpty) return 1;
    final counts = <double, int>{};
    for (final log in logs) {
      counts.update(log.amount, (value) => value + 1, ifAbsent: () => 1);
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: formatQuantity(_isUse ? _suggestedAmount() : 1),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_amount.text.trim());

  String? get _error {
    final value = _parsed;
    if (value == null || value <= 0) return 'Enter an amount above zero';
    if (_isUse && value > widget.item.quantity) {
      return 'Only ${formatQuantity(widget.item.quantity)} '
          '${widget.item.unit} left';
    }
    return null;
  }

  Future<void> _save() async {
    if (_error != null) return;
    setState(() => _saving = true);
    try {
      final log = await ref
          .read(inventoryProvider.notifier)
          .applyAction(
            itemId: widget.item.id,
            itemType: widget.item.kind,
            action: widget.action,
            amount: _parsed!,
            note: _note.text,
            date: _date,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop(log);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'When was it logged?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final item = widget.item;
    final after = switch (widget.action) {
      InventoryAction.restock => item.quantity + (_parsed ?? 0),
      _ => (item.quantity - (_parsed ?? 0))
          .clamp(0, double.infinity)
          .toDouble(),
    };
    final metrics = jarMetrics(
      quantity: after,
      initialQuantity: item.initialQuantity,
      threshold: item.threshold,
      piecewise: item.piecewise,
    );

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isUse
                            ? (item.isChemical ? 'Log use' : 'Log breakage')
                            : 'Restock',
                        style: TextStyle(
                          fontFamily: 'Caveat',
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: lab.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(item.name, style: context.itemName),
                    ],
                  ),
                ),
                GlassJar(metrics: metrics, width: 40, height: 50),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: true,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: context.figure.copyWith(fontSize: 24),
                    decoration: InputDecoration(
                      labelText: _isUse ? 'Amount' : 'Amount added',
                      suffixText: item.unit,
                      errorText: _amount.text.isEmpty ? null : _error,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${formatQuantity(item.quantity)} → '
                    '${formatQuantity(after)}',
                    style: context.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Titration, group 3',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined, size: 17),
                  label: Text(
                    DateFormat('d MMM').format(_date),
                    style: const TextStyle(fontFamily: 'Caveat', fontSize: 18),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving || _error != null ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isUse ? 'Record' : 'Add to stock'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
