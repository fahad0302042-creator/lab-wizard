import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_jar.dart';
import '../../../core/widgets/jar_metrics.dart';
import '../../inventory/domain/models.dart';

/// What just happened, so the shelf can offer to undo it.
class LoggedAction {
  const LoggedAction({
    required this.chemical,
    required this.action,
    required this.amount,
  });

  final Chemical chemical;
  final InventoryAction action;
  final double amount;

  InventoryAction get inverse => switch (action) {
    InventoryAction.consume || InventoryAction.breakage =>
      InventoryAction.restock,
    InventoryAction.restock => InventoryAction.consume,
  };
}

/// Records use or restock for one item.
///
/// The amount is pre-filled with the last amount logged for that item, because
/// a lab tends to use the same amount repeatedly — one tap usually does it.
Future<LoggedAction?> showActionSheet(
  BuildContext context,
  WidgetRef ref, {
  required Chemical chemical,
  required InventoryAction action,
}) {
  return showModalBottomSheet<LoggedAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ActionSheet(chemical: chemical, action: action),
  );
}

class _ActionSheet extends ConsumerStatefulWidget {
  const _ActionSheet({required this.chemical, required this.action});

  final Chemical chemical;
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

  /// The most common amount for this item, from its own history.
  double _suggestedAmount() {
    final logs = ref
        .read(inventoryProvider)
        .logs
        .where(
          (log) =>
              log.itemId == widget.chemical.id &&
              (log.action == InventoryAction.consume ||
                  log.action == InventoryAction.breakage),
        )
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
    if (_isUse && value > widget.chemical.quantity) {
      return 'Only ${formatQuantity(widget.chemical.quantity)} '
          '${widget.chemical.unit} left';
    }
    return null;
  }

  Future<void> _save() async {
    if (_error != null) return;
    setState(() => _saving = true);
    final amount = _parsed!;
    try {
      await ref
          .read(inventoryProvider.notifier)
          .applyAction(
            itemId: widget.chemical.id,
            itemType: ItemKind.chemical,
            action: widget.action,
            amount: amount,
            note: _note.text,
            date: _date,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final result = LoggedAction(
        chemical: widget.chemical,
        action: widget.action,
        amount: amount,
      );
      Navigator.of(context).pop(result);
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
      helpText: 'When was it used?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final chemical = widget.chemical;
    final after = switch (widget.action) {
      InventoryAction.restock => chemical.quantity + (_parsed ?? 0),
      _ => (chemical.quantity - (_parsed ?? 0)).clamp(0, double.infinity),
    };
    final metrics = jarMetrics(
      quantity: after,
      initialQuantity: chemical.initialQuantity,
      threshold: chemical.lowStockThreshold,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                        _isUse ? 'Log use' : 'Restock',
                        style: TextStyle(
                          fontFamily: 'Caveat',
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: lab.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(chemical.name, style: context.itemName),
                    ],
                  ),
                ),
                // Live preview: the jar updates as you type, so you see the
                // level before you commit.
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
                      labelText: _isUse ? 'Amount used' : 'Amount added',
                      suffixText: chemical.unit,
                      errorText: _amount.text.isEmpty ? null : _error,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${formatQuantity(chemical.quantity)} → '
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
                      : Text(_isUse ? 'Record use' : 'Add to stock'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
