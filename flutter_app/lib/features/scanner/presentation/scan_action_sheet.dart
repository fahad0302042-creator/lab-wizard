import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../inventory/domain/lab_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';

/// What the quick-action sheet did before it closed.
class ScanActionResult {
  const ScanActionResult({this.message, this.openDetails = false});

  /// One-line confirmation such as "Used 5 mL of Acetone · 45 mL left".
  final String? message;

  /// The user asked for the full item sheet instead.
  final bool openDetails;
}

/// Quick amount + consume / restock / damage / return right after a label was
/// recognised (SCAN-03). Resolves to null when dismissed without a change.
Future<ScanActionResult?> showScanActionSheet(
  BuildContext context, {
  required ItemKind kind,
  required String itemId,
}) {
  return showModalBottomSheet<ScanActionResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NotebookSheetFrame(
      child: ScanActionForm(kind: kind, itemId: itemId),
    ),
  );
}

/// Amounts offered as one-tap chips.
List<double> quickAmountsFor(ItemKind kind) =>
    kind == ItemKind.chemical ? const [1, 5, 10, 25, 50] : const [1, 2, 5, 10];

/// Confirmation line for a stock action recorded from the scanner.
String scanActionMessage({
  required InventoryAction action,
  required String name,
  required double amount,
  required String unit,
  required double after,
}) {
  final quantity = '${formatQuantity(amount)} $unit'.trim();
  final left = '${formatQuantity(after)} $unit'.trim();
  return switch (action) {
    InventoryAction.consume => 'Used $quantity of $name · $left left',
    InventoryAction.restock => 'Restocked $quantity of $name · now $left',
    InventoryAction.breakage =>
      'Damage recorded, $quantity of $name · $left left',
  };
}

class ScanActionForm extends ConsumerStatefulWidget {
  const ScanActionForm({required this.kind, required this.itemId, super.key});

  final ItemKind kind;
  final String itemId;

  @override
  ConsumerState<ScanActionForm> createState() => _ScanActionFormState();
}

class _ScanActionFormState extends ConsumerState<ScanActionForm> {
  final _amount = TextEditingController();
  InventoryAction? _busy;
  bool _returning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final remembered = ref
        .read(formMemoryProvider)
        .amountFor(widget.kind, InventoryAction.consume);
    final initial =
        remembered ?? (widget.kind == ItemKind.apparatus ? 1.0 : null);
    if (initial != null) _amount.text = formatQuantity(initial);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _working => _busy != null || _returning;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(visibleInventoryProvider);
    final chemical = widget.kind == ItemKind.chemical
        ? state.chemicals.where((item) => item.id == widget.itemId).firstOrNull
        : null;
    final apparatus = widget.kind == ItemKind.apparatus
        ? state.apparatus.where((item) => item.id == widget.itemId).firstOrNull
        : null;
    if (chemical == null && apparatus == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SketchTitle('not found', fontSize: 30),
          const Text('This item is no longer in your notebook.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final name = chemical?.name ?? apparatus!.name;
    final subtitle = chemical != null
        ? chemical.formula
        : [
            apparatus!.category.replaceAll('_', ' '),
            if ((apparatus.serialNumber ?? '').isNotEmpty)
              'S/N ${apparatus.serialNumber}',
          ].join(' · ');
    final unit = chemical?.unit ?? 'pcs';
    final current = chemical?.quantity ?? apparatus!.quantity;
    final threshold =
        chemical?.lowStockThreshold ?? apparatus!.lowStockThreshold;
    final loans = apparatus == null
        ? const <ApparatusCheckout>[]
        : state.checkouts
              .where((loan) => loan.apparatusId == apparatus.id && loan.isOpen)
              .toList();
    final onLoan = loans.fold(0.0, (sum, loan) => sum + loan.outstanding);
    final muted = context.mutedInkColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SketchTitle(name, fontSize: 28),
        if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: muted)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              widget.kind == ItemKind.chemical
                  ? Icons.science_outlined
                  : Icons.precision_manufacturing_outlined,
              size: 20,
              color: current <= threshold ? context.lowColor : muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  '${formatQuantity(current)} $unit in stock',
                  if (current <= threshold) 'low',
                  if (onLoan > 0) '${formatQuantity(onLoan)} on loan',
                ].join(' · '),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: current <= threshold ? context.lowColor : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('scan-amount'),
          controller: _amount,
          enabled: !_working,
          keyboardType: TextInputType.numberWithOptions(
            decimal: widget.kind == ItemKind.chemical,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: unit,
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final amount in quickAmountsFor(widget.kind))
              ActionChip(
                key: Key('scan-chip-${formatQuantity(amount)}'),
                label: Text(formatQuantity(amount)),
                onPressed: _working
                    ? null
                    : () => setState(() {
                        _amount.text = formatQuantity(amount);
                        _error = null;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('scan-use'),
                onPressed: _working || current <= 0
                    ? null
                    : () => _run(InventoryAction.consume),
                style: FilledButton.styleFrom(
                  backgroundColor: context.lowColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: _busy == InventoryAction.consume
                    ? const _Spinner()
                    : const Icon(Icons.remove),
                label: const Text('Use'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const Key('scan-restock'),
                onPressed: _working
                    ? null
                    : () => _run(InventoryAction.restock),
                style: FilledButton.styleFrom(
                  backgroundColor: context.healthyColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: _busy == InventoryAction.restock
                    ? const _Spinner()
                    : const Icon(Icons.add),
                label: const Text('Restock'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('scan-damage'),
                onPressed: _working || current <= 0
                    ? null
                    : () => _run(InventoryAction.breakage),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.marginRedColor,
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: _busy == InventoryAction.breakage
                    ? const _Spinner()
                    : const Icon(Icons.broken_image_outlined),
                label: const Text('Damage'),
              ),
            ),
            if (loans.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('scan-return'),
                  onPressed: _working ? null : () => _return(loans),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: _returning
                      ? const _Spinner()
                      : const Icon(Icons.assignment_return_outlined),
                  label: Text('Return (${formatQuantity(onLoan)} out)'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          key: const Key('scan-details'),
          onPressed: _working
              ? null
              : () =>
                    Navigator.of(context)
                        .pop(const ScanActionResult(openDetails: true)),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Open details'),
        ),
      ],
    );
  }

  double? _readAmount() {
    final value = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return null;
    }
    return value;
  }

  Future<void> _run(InventoryAction action) async {
    final amount = _readAmount();
    if (amount == null) return;
    setState(() {
      _busy = action;
      _error = null;
    });
    final notifier = ref.read(inventoryProvider.notifier);
    try {
      final log = await notifier.applyAction(
        itemId: widget.itemId,
        itemType: widget.kind,
        action: action,
        amount: amount,
        note: 'via scanner',
        date: DateTime.now(),
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      unawaited(
        ref
            .read(formMemoryProvider.notifier)
            .rememberAmount(widget.kind, action, log.amount),
      );
      final state = ref.read(visibleInventoryProvider);
      final chemical = widget.kind == ItemKind.chemical
          ? state.chemicals
                .where((item) => item.id == widget.itemId)
                .firstOrNull
          : null;
      final apparatus = widget.kind == ItemKind.apparatus
          ? state.apparatus
                .where((item) => item.id == widget.itemId)
                .firstOrNull
          : null;
      final message = scanActionMessage(
        action: action,
        name: chemical?.name ?? apparatus?.name ?? 'item',
        amount: log.amount,
        unit: chemical?.unit ?? (apparatus == null ? '' : 'pcs'),
        after: chemical?.quantity ?? apparatus?.quantity ?? 0,
      );
      final messenger = ScaffoldMessenger.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      Navigator.of(context).pop(ScanActionResult(message: message));
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => undoRecordedAction(container, messenger, log.id),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _return(List<ApparatusCheckout> loans) async {
    final amount = _readAmount();
    if (amount == null) return;
    ApparatusCheckout? loan = loans.length == 1 ? loans.single : null;
    if (loan == null) {
      loan = await showDialog<ApparatusCheckout>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Which loan is coming back?'),
          children: [
            for (final option in loans)
              SimpleDialogOption(
                key: Key('scan-loan-${option.id}'),
                onPressed: () => Navigator.of(dialogContext).pop(option),
                child: Text(
                  '${option.person.isEmpty ? 'Unnamed' : option.person} · '
                  '${formatQuantity(option.outstanding)} out'
                  '${option.isOverdue() ? ' · overdue' : ''}',
                ),
              ),
          ],
        ),
      );
      if (loan == null || !mounted) return;
    }
    setState(() {
      _returning = true;
      _error = null;
    });
    try {
      await ref
          .read(inventoryProvider.notifier)
          .returnApparatus(
            checkoutId: loan.id,
            quantity: amount,
            note: 'via scanner',
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final apparatus = ref
          .read(visibleInventoryProvider)
          .apparatus
          .where((item) => item.id == widget.itemId)
          .firstOrNull;
      final message =
          'Returned ${formatQuantity(amount)} of ${apparatus?.name ?? 'item'}'
          '${apparatus == null ? '' : ' · ${formatQuantity(apparatus.quantity)} pcs in stock'}';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(ScanActionResult(message: message));
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _returning = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
