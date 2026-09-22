import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/lab_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';
import 'inventory_sheets.dart';

/// Batch restock for the selected items (BATCH-01). Every item gets its own
/// amount and its own audit entry.
Future<void> showBatchRestockSheet(
  BuildContext context, {
  required ItemKind kind,
  required Set<String> itemIds,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => NotebookSheetFrame(
    child: _BatchRestockForm(kind: kind, itemIds: itemIds),
  ),
);

/// Batch low-stock threshold with an old → new preview (BATCH-02).
Future<void> showBatchThresholdSheet(
  BuildContext context, {
  required ItemKind kind,
  required Set<String> itemIds,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => NotebookSheetFrame(
    child: _BatchThresholdForm(kind: kind, itemIds: itemIds),
  ),
);

/// Batch storage location (chemicals) or category (apparatus) with an
/// old → new preview (BATCH-03). The field is chosen by the shelf, so a
/// value can never be written to an item type that does not have it.
Future<void> showBatchFieldSheet(
  BuildContext context, {
  required ItemKind kind,
  required Set<String> itemIds,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => NotebookSheetFrame(
    child: _BatchFieldForm(kind: kind, itemIds: itemIds),
  ),
);

/// Guarded multi-delete (BATCH-04): summary, unsynced/offline checks, typed
/// confirmation for large deletions and a per-item result report.
Future<void> showBatchDeleteSheet(
  BuildContext context, {
  required ItemKind kind,
  required Set<String> itemIds,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => NotebookSheetFrame(
    child: _BatchDeleteForm(kind: kind, itemIds: itemIds),
  ),
);

/// Deletions of this many items or more must be confirmed by typing.
const largeDeletionThreshold = 5;

/// Word the user types to confirm a large deletion.
const deleteConfirmationWord = 'DELETE';

class BatchFailure {
  const BatchFailure({
    required this.itemId,
    required this.name,
    required this.message,
  });

  final String itemId;
  final String name;
  final String message;
}

class BatchOutcome {
  const BatchOutcome({required this.succeeded, required this.failures});

  final int succeeded;
  final List<BatchFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

/// Applies [step] to every item in order. A failure never stops the rest of
/// the batch; it is reported so the user can retry just the failed rows.
Future<BatchOutcome> runBatch<T>({
  required List<T> items,
  required String Function(T item) idOf,
  required String Function(T item) nameOf,
  required Future<void> Function(T item) step,
  void Function(int done)? onProgress,
}) async {
  var succeeded = 0;
  final failures = <BatchFailure>[];
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    try {
      await step(item);
      succeeded++;
    } catch (error) {
      failures.add(
        BatchFailure(
          itemId: idOf(item),
          name: nameOf(item),
          message: friendlyErrorMessage(error),
        ),
      );
    }
    onProgress?.call(index + 1);
  }
  return BatchOutcome(succeeded: succeeded, failures: failures);
}

/// Validates a typed quantity. Apparatus counts must be whole numbers.
String? validateBatchAmount(
  String text, {
  required bool wholeNumbers,
  bool allowZero = false,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 'Enter an amount';
  final value = double.tryParse(trimmed);
  if (value == null || value.isNaN || value.isInfinite) {
    return 'Enter a number';
  }
  if (value < 0 || (!allowZero && value == 0)) {
    return allowZero ? 'Cannot be negative' : 'Must be greater than zero';
  }
  if (wholeNumbers && value != value.roundToDouble()) {
    return 'Use whole numbers for apparatus';
  }
  return null;
}

class _BatchItem {
  const _BatchItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.threshold,
    required this.unit,
    this.field = '',
  });

  final String id;
  final String name;
  final double quantity;
  final double threshold;
  final String unit;

  /// Current value of the BATCH-03 field: location for chemicals, category
  /// for apparatus.
  final String field;
}

List<_BatchItem> _itemsFor(
  InventoryState state,
  ItemKind kind,
  Set<String> ids,
) {
  final items = kind == ItemKind.chemical
      ? [
          for (final item in state.chemicals)
            if (ids.contains(item.id))
              _BatchItem(
                id: item.id,
                name: item.name,
                quantity: item.quantity,
                threshold: item.lowStockThreshold,
                unit: item.unit,
                field: item.location ?? '',
              ),
        ]
      : [
          for (final item in state.apparatus)
            if (ids.contains(item.id))
              _BatchItem(
                id: item.id,
                name: item.name,
                quantity: item.quantity,
                threshold: item.lowStockThreshold,
                unit: 'pcs',
                field: item.category,
              ),
        ];
  items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return items;
}

class _BatchRestockForm extends ConsumerStatefulWidget {
  const _BatchRestockForm({required this.kind, required this.itemIds});

  final ItemKind kind;
  final Set<String> itemIds;

  @override
  ConsumerState<_BatchRestockForm> createState() => _BatchRestockFormState();
}

class _BatchRestockFormState extends ConsumerState<_BatchRestockForm> {
  final _amounts = <String, TextEditingController>{};
  final _sameAmount = TextEditingController();
  final _note = TextEditingController(text: 'Batch restock');
  bool _showErrors = false;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  BatchOutcome? _outcome;

  bool get _whole => widget.kind == ItemKind.apparatus;

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    _sameAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFor(
      ref.watch(visibleInventoryProvider),
      widget.kind,
      widget.itemIds,
    );
    final outcome = _outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading('batch restock'),
        Text(
          '${items.length} ${widget.kind == ItemKind.chemical ? 'reagents' : 'items'} selected. '
          'Each restock keeps its own history entry and can be undone one by one.',
          style: TextStyle(color: context.mutedInkColor),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const EmptyNotebookState(
            icon: Icons.checklist,
            title: 'nothing selected',
            message: 'Pick items on the shelf first.',
          )
        else if (outcome != null && outcome.hasFailures)
          _BatchReport(
            outcome: outcome,
            verb: 'restocked',
            onRetry: _running ? null : () => _run(items, onlyFailed: true),
            onClose: () => Navigator.pop(context),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('batch-same-amount'),
                  controller: _sameAmount,
                  enabled: !_running,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !_whole,
                  ),
                  decoration: InputDecoration(
                    labelText: 'same amount for all',
                    suffixText: widget.kind == ItemKind.apparatus
                        ? 'pcs'
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('batch-apply-same'),
                onPressed: _running ? null : () => _fillAll(items),
                child: const Text('apply'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _AmountRow(
                item: item,
                controller: _controllerFor(item.id),
                enabled: !_running,
                error: _showErrors
                    ? validateBatchAmount(
                        _controllerFor(item.id).text,
                        wholeNumbers: _whole,
                      )
                    : null,
                onChanged: () => setState(() {}),
              ),
            ),
          TextField(
            controller: _note,
            enabled: !_running,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'note (optional)'),
          ),
          const SizedBox(height: 14),
          if (_running) _BatchProgress(done: _done, total: _total),
          FilledButton.icon(
            key: const Key('batch-restock-submit'),
            onPressed: _running ? null : () => _run(items),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_circle_outline),
            label: Text(
              _running
                  ? 'Restocking $_done of $_total…'
                  : 'Restock ${items.length} item${items.length == 1 ? '' : 's'}',
            ),
          ),
        ],
      ],
    );
  }

  TextEditingController _controllerFor(String id) =>
      _amounts.putIfAbsent(id, TextEditingController.new);

  void _fillAll(List<_BatchItem> items) {
    final text = _sameAmount.text.trim();
    setState(() {
      for (final item in items) {
        _controllerFor(item.id).text = text;
      }
    });
  }

  Future<void> _run(List<_BatchItem> items, {bool onlyFailed = false}) async {
    final previous = _outcome;
    final targets = onlyFailed && previous != null
        ? items
              .where(
                (item) => previous.failures.any(
                  (failure) => failure.itemId == item.id,
                ),
              )
              .toList()
        : items;
    final invalid = targets.any(
      (item) =>
          validateBatchAmount(
            _controllerFor(item.id).text,
            wholeNumbers: _whole,
          ) !=
          null,
    );
    if (invalid) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the highlighted amounts.')),
      );
      return;
    }
    setState(() {
      _running = true;
      _done = 0;
      _total = targets.length;
      _outcome = null;
    });
    final controller = ref.read(inventoryProvider.notifier);
    final note = _note.text.trim();
    final outcome = await runBatch<_BatchItem>(
      items: targets,
      idOf: (item) => item.id,
      nameOf: (item) => item.name,
      step: (item) => controller.applyAction(
        itemId: item.id,
        itemType: widget.kind,
        action: InventoryAction.restock,
        amount: double.parse(_controllerFor(item.id).text.trim()),
        note: note,
        date: DateTime.now(),
      ),
      onProgress: (done) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    final restocked = (previous?.succeeded ?? 0) + outcome.succeeded;
    setState(() {
      _running = false;
      _outcome = BatchOutcome(succeeded: restocked, failures: outcome.failures);
    });
    if (outcome.hasFailures) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context)
      // A stale "check the amounts" note must not delay the result.
      ..clearSnackBars();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('$restocked item${restocked == 1 ? '' : 's'} restocked'),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.item,
    required this.controller,
    required this.enabled,
    required this.error,
    required this.onChanged,
  });

  final _BatchItem item;
  final TextEditingController controller;
  final bool enabled;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return NotebookCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'now ${formatQuantity(item.quantity)} ${item.unit}',
                  style: TextStyle(color: context.mutedInkColor, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(
              key: Key('batch-amount-${item.id}'),
              controller: controller,
              enabled: enabled,
              onChanged: (_) => onChanged(),
              keyboardType: TextInputType.numberWithOptions(
                decimal: item.unit != 'pcs',
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                suffixText: item.unit,
                errorText: error,
                errorMaxLines: 2,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchThresholdForm extends ConsumerStatefulWidget {
  const _BatchThresholdForm({required this.kind, required this.itemIds});

  final ItemKind kind;
  final Set<String> itemIds;

  @override
  ConsumerState<_BatchThresholdForm> createState() =>
      _BatchThresholdFormState();
}

class _BatchThresholdFormState extends ConsumerState<_BatchThresholdForm> {
  final _value = TextEditingController();
  bool _running = false;
  int _done = 0;
  int _total = 0;
  BatchOutcome? _outcome;

  bool get _whole => widget.kind == ItemKind.apparatus;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFor(
      ref.watch(visibleInventoryProvider),
      widget.kind,
      widget.itemIds,
    );
    final error = _value.text.trim().isEmpty
        ? null
        : validateBatchAmount(
            _value.text,
            wholeNumbers: _whole,
            allowZero: true,
          );
    final parsed = error == null ? double.tryParse(_value.text.trim()) : null;
    final changed = parsed == null
        ? const <_BatchItem>[]
        : items.where((item) => item.threshold != parsed).toList();
    final outcome = _outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading('batch threshold'),
        Text(
          'Set one low-stock threshold for ${items.length} selected '
          '${widget.kind == ItemKind.chemical ? 'reagents' : 'items'}. '
          'Items already at that value are left untouched.',
          style: TextStyle(color: context.mutedInkColor),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const EmptyNotebookState(
            icon: Icons.checklist,
            title: 'nothing selected',
            message: 'Pick items on the shelf first.',
          )
        else if (outcome != null && outcome.hasFailures)
          _BatchReport(
            outcome: outcome,
            verb: 'updated',
            onRetry: _running ? null : () => _run(changed, onlyFailed: true),
            onClose: () => Navigator.pop(context),
          )
        else ...[
          TextField(
            key: const Key('batch-threshold-value'),
            controller: _value,
            enabled: !_running,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.numberWithOptions(decimal: !_whole),
            decoration: InputDecoration(
              labelText: 'new low-stock threshold',
              helperText: _whole
                  ? 'whole number of pieces; 0 turns the warning off'
                  : 'in each item\'s own unit; 0 turns the warning off',
              errorText: error,
            ),
          ),
          const SizedBox(height: 12),
          const PageHeading('preview', fontSize: 27),
          for (final item in items)
            ListTile(
              key: Key('threshold-preview-${item.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                parsed == null
                    ? Icons.horizontal_rule
                    : item.threshold == parsed
                    ? Icons.check
                    : Icons.arrow_forward,
                size: 18,
                color: context.mutedInkColor,
              ),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                parsed == null
                    ? 'min ${formatQuantity(item.threshold)} ${item.unit}'
                    : item.threshold == parsed
                    ? 'already ${formatQuantity(parsed)} ${item.unit} — unchanged'
                    : 'min ${formatQuantity(item.threshold)} → ${formatQuantity(parsed)} ${item.unit}',
              ),
            ),
          const SizedBox(height: 14),
          if (_running) _BatchProgress(done: _done, total: _total),
          FilledButton.icon(
            key: const Key('batch-threshold-submit'),
            onPressed: _running || parsed == null || changed.isEmpty
                ? null
                : () => _run(changed),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.tune),
            label: Text(
              _running
                  ? 'Updating $_done of $_total…'
                  : parsed == null
                  ? 'Enter a threshold'
                  : changed.isEmpty
                  ? 'Nothing to change'
                  : 'Update ${changed.length} item${changed.length == 1 ? '' : 's'}',
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _run(List<_BatchItem> items, {bool onlyFailed = false}) async {
    final previous = _outcome;
    final targets = onlyFailed && previous != null
        ? items
              .where(
                (item) => previous.failures.any(
                  (failure) => failure.itemId == item.id,
                ),
              )
              .toList()
        : items;
    final value = double.parse(_value.text.trim());
    setState(() {
      _running = true;
      _done = 0;
      _total = targets.length;
      _outcome = null;
    });
    final controller = ref.read(inventoryProvider.notifier);
    final outcome = await runBatch<_BatchItem>(
      items: targets,
      idOf: (item) => item.id,
      nameOf: (item) => item.name,
      step: (item) => controller.updateItem(
        type: widget.kind,
        id: item.id,
        changes: {'low_stock_threshold': value},
      ),
      onProgress: (done) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    final updated = (previous?.succeeded ?? 0) + outcome.succeeded;
    setState(() {
      _running = false;
      _outcome = BatchOutcome(succeeded: updated, failures: outcome.failures);
    });
    if (outcome.hasFailures) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context)
      // A stale "check the amounts" note must not delay the result.
      ..clearSnackBars();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Threshold updated for $updated item${updated == 1 ? '' : 's'}',
        ),
      ),
    );
  }
}

/// Known apparatus categories, matching the add/edit sheets.
const apparatusCategories = [
  'glassware',
  'balances',
  'heating',
  'measurement',
  'other',
];

class _BatchFieldForm extends ConsumerStatefulWidget {
  const _BatchFieldForm({required this.kind, required this.itemIds});

  final ItemKind kind;
  final Set<String> itemIds;

  @override
  ConsumerState<_BatchFieldForm> createState() => _BatchFieldFormState();
}

class _BatchFieldFormState extends ConsumerState<_BatchFieldForm> {
  final _value = TextEditingController();
  String? _category;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  BatchOutcome? _outcome;

  bool get _chemical => widget.kind == ItemKind.chemical;
  String get _fieldLabel => _chemical ? 'location' : 'category';
  String get _column => _chemical ? 'location' : 'category';

  /// The new value, or null while nothing valid has been entered.
  String? get _target {
    if (_chemical) {
      final text = _value.text.trim();
      return text.isEmpty ? null : text;
    }
    return _category;
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(visibleInventoryProvider);
    final items = _itemsFor(state, widget.kind, widget.itemIds);
    final target = _target;
    final changed = target == null
        ? const <_BatchItem>[]
        : items.where((item) => item.field != target).toList();
    final outcome = _outcome;
    final suggestions = _chemical
        ? ({
            for (final item in state.chemicals)
              if ((item.location ?? '').trim().isNotEmpty)
                item.location!.trim(),
          }.toList()..sort())
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading('batch $_fieldLabel'),
        Text(
          _chemical
              ? 'Move ${items.length} selected reagents to one storage '
                    'location. Items already there are left untouched.'
              : 'Put ${items.length} selected items in one category. Items '
                    'already in it are left untouched.',
          style: TextStyle(color: context.mutedInkColor),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const EmptyNotebookState(
            icon: Icons.checklist,
            title: 'nothing selected',
            message: 'Pick items on the shelf first.',
          )
        else if (outcome != null && outcome.hasFailures)
          _BatchReport(
            outcome: outcome,
            verb: 'updated',
            onRetry: _running ? null : () => _run(changed, onlyFailed: true),
            onClose: () => Navigator.pop(context),
          )
        else ...[
          if (_chemical) ...[
            TextField(
              key: const Key('batch-field-value'),
              controller: _value,
              enabled: !_running,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'new storage location',
                hintText: 'Cabinet B, shelf 2',
                helperText: 'Needs the 003 chemical metadata database script.',
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final suggestion in suggestions.take(8))
                    ActionChip(
                      key: Key('location-suggestion-$suggestion'),
                      label: Text(suggestion),
                      onPressed: _running
                          ? null
                          : () => setState(() => _value.text = suggestion),
                    ),
                ],
              ),
            ],
          ] else
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('batch-field-category'),
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'new category'),
              items: [
                for (final category in apparatusCategories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: _running
                  ? null
                  : (value) => setState(() => _category = value),
            ),
          const SizedBox(height: 12),
          const PageHeading('preview', fontSize: 27),
          for (final item in items)
            ListTile(
              key: Key('field-preview-${item.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                target == null
                    ? Icons.horizontal_rule
                    : item.field == target
                    ? Icons.check
                    : Icons.arrow_forward,
                size: 18,
                color: context.mutedInkColor,
              ),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                target == null
                    ? (item.field.isEmpty ? 'no $_fieldLabel yet' : item.field)
                    : item.field == target
                    ? 'already $target — unchanged'
                    : '${item.field.isEmpty ? 'none' : item.field} → $target',
              ),
            ),
          const SizedBox(height: 14),
          if (_running) _BatchProgress(done: _done, total: _total),
          FilledButton.icon(
            key: const Key('batch-field-submit'),
            onPressed: _running || target == null || changed.isEmpty
                ? null
                : () => _run(changed),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _chemical ? Icons.place_outlined : Icons.category_outlined,
                  ),
            label: Text(
              _running
                  ? 'Updating $_done of $_total…'
                  : target == null
                  ? 'Enter a $_fieldLabel'
                  : changed.isEmpty
                  ? 'Nothing to change'
                  : 'Update ${changed.length} item${changed.length == 1 ? '' : 's'}',
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _run(List<_BatchItem> items, {bool onlyFailed = false}) async {
    final previous = _outcome;
    final targets = onlyFailed && previous != null
        ? items
              .where(
                (item) => previous.failures.any(
                  (failure) => failure.itemId == item.id,
                ),
              )
              .toList()
        : items;
    final value = _target;
    if (value == null) return;
    setState(() {
      _running = true;
      _done = 0;
      _total = targets.length;
      _outcome = null;
    });
    final controller = ref.read(inventoryProvider.notifier);
    final outcome = await runBatch<_BatchItem>(
      items: targets,
      idOf: (item) => item.id,
      nameOf: (item) => item.name,
      step: (item) => controller.updateItem(
        type: widget.kind,
        id: item.id,
        changes: {_column: value},
      ),
      onProgress: (done) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    final updated = (previous?.succeeded ?? 0) + outcome.succeeded;
    setState(() {
      _running = false;
      _outcome = BatchOutcome(succeeded: updated, failures: outcome.failures);
    });
    if (outcome.hasFailures) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context)
      // A stale "check the amounts" note must not delay the result.
      ..clearSnackBars();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${_chemical ? 'Location' : 'Category'} updated for $updated '
          'item${updated == 1 ? '' : 's'}',
        ),
      ),
    );
  }
}

class _BatchDeleteForm extends ConsumerStatefulWidget {
  const _BatchDeleteForm({required this.kind, required this.itemIds});

  final ItemKind kind;
  final Set<String> itemIds;

  @override
  ConsumerState<_BatchDeleteForm> createState() => _BatchDeleteFormState();
}

class _BatchDeleteFormState extends ConsumerState<_BatchDeleteForm> {
  final _confirmation = TextEditingController();
  bool _running = false;
  bool _checkingConnection = false;
  int _done = 0;
  int _total = 0;
  String? _blocker;
  BatchOutcome? _outcome;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(visibleInventoryProvider);
    final items = _itemsFor(state, widget.kind, widget.itemIds);
    final ids = {for (final item in items) item.id};
    final logCount = state.logs.where((log) => ids.contains(log.itemId)).length;
    final unsynced = items
        .where(
          (item) =>
              state.outbox.any((operation) => operation.itemId == item.id),
        )
        .toList();
    final large = items.length >= largeDeletionThreshold;
    final typed =
        _confirmation.text.trim().toUpperCase() == deleteConfirmationWord;
    final outcome = _outcome;
    final canDelete =
        items.isNotEmpty &&
        unsynced.isEmpty &&
        !_running &&
        !_checkingConnection &&
        (!large || typed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading('delete items'),
        if (items.isEmpty)
          const EmptyNotebookState(
            icon: Icons.checklist,
            title: 'nothing selected',
            message: 'Pick items on the shelf first.',
          )
        else if (outcome != null && outcome.hasFailures)
          _BatchReport(
            outcome: outcome,
            verb: 'deleted',
            onRetry: _running ? null : () => _run(items, onlyFailed: true),
            onClose: () => Navigator.pop(context),
          )
        else ...[
          NotebookCard(
            accent: context.marginRedColor,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'} and '
                  '$logCount history entr${logCount == 1 ? 'y' : 'ies'} will be '
                  'removed for everyone using this account.',
                  key: const Key('batch-delete-summary'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'This cannot be undone. Export a CSV from Settings first if '
                  'you need to keep a record.',
                  style: TextStyle(color: context.mutedInkColor, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final item in items.take(12))
                Chip(
                  label: Text(item.name, overflow: TextOverflow.ellipsis),
                  visualDensity: VisualDensity.compact,
                ),
              if (items.length > 12)
                Chip(
                  label: Text('and ${items.length - 12} more'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (unsynced.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${unsynced.length} of these still ${unsynced.length == 1 ? 'has' : 'have'} '
              'unsynced changes (${unsynced.map((item) => item.name).take(3).join(', ')}'
              '${unsynced.length > 3 ? ', …' : ''}). Sync first, then delete.',
              key: const Key('batch-delete-unsynced'),
              style: TextStyle(color: context.marginRedColor),
            ),
          ],
          if (_blocker != null) ...[
            const SizedBox(height: 10),
            Text(
              _blocker!,
              key: const Key('batch-delete-blocker'),
              style: TextStyle(color: context.marginRedColor),
            ),
          ],
          if (large) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('batch-delete-confirmation'),
              controller: _confirmation,
              enabled: !_running,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'type $deleteConfirmationWord to confirm',
                helperText:
                    'Required when deleting $largeDeletionThreshold or more items.',
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_running) _BatchProgress(done: _done, total: _total),
          FilledButton.icon(
            key: const Key('batch-delete-submit'),
            onPressed: canDelete ? () => _run(items) : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: LabColors.marginRed,
            ),
            icon: _running || _checkingConnection
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: Text(
              _running
                  ? 'Deleting $_done of $_total…'
                  : _checkingConnection
                  ? 'Checking connection…'
                  : 'Delete ${items.length} item${items.length == 1 ? '' : 's'}',
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _running ? null : () => Navigator.pop(context),
            child: const Text('Keep everything'),
          ),
        ],
      ],
    );
  }

  Future<void> _run(List<_BatchItem> items, {bool onlyFailed = false}) async {
    final previous = _outcome;
    final targets = onlyFailed && previous != null
        ? items
              .where(
                (item) => previous.failures.any(
                  (failure) => failure.itemId == item.id,
                ),
              )
              .toList()
        : items;
    setState(() {
      _checkingConnection = true;
      _blocker = null;
    });
    // The repository refuses to queue deletions; this only avoids starting a
    // batch that is certain to fail on a device with no network at all.
    final online = await ref.read(isOnlineProvider)();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _checkingConnection = false;
        _blocker =
            'Deleting needs an internet connection so nothing is left half '
            'done. Connect and try again.';
      });
      return;
    }
    setState(() {
      _checkingConnection = false;
      _running = true;
      _done = 0;
      _total = targets.length;
      _outcome = null;
    });
    final controller = ref.read(inventoryProvider.notifier);
    final outcome = await runBatch<_BatchItem>(
      items: targets,
      idOf: (item) => item.id,
      nameOf: (item) => item.name,
      step: (item) => controller.deleteItem(widget.kind, item.id),
      onProgress: (done) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    final deleted = (previous?.succeeded ?? 0) + outcome.succeeded;
    setState(() {
      _running = false;
      _outcome = BatchOutcome(succeeded: deleted, failures: outcome.failures);
    });
    if (outcome.hasFailures) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context)
      // A stale "check the amounts" note must not delay the result.
      ..clearSnackBars();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('$deleted item${deleted == 1 ? '' : 's'} deleted'),
      ),
    );
  }
}

class _BatchProgress extends StatelessWidget {
  const _BatchProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            key: const Key('batch-progress'),
            value: total == 0 ? null : done / total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 4),
          Text(
            '$done of $total',
            style: TextStyle(color: context.mutedInkColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BatchReport extends StatelessWidget {
  const _BatchReport({
    required this.outcome,
    required this.verb,
    required this.onRetry,
    required this.onClose,
  });

  final BatchOutcome outcome;
  final String verb;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookCard(
          accent: context.marginRedColor,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Text(
            '${outcome.succeeded} $verb · ${outcome.failures.length} failed',
            key: const Key('batch-report'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        for (final failure in outcome.failures)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.error_outline, color: context.marginRedColor),
            title: Text(failure.name),
            subtitle: Text(failure.message),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('batch-retry-failed'),
          onPressed: onRetry,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.replay),
          label: Text('Retry ${outcome.failures.length} failed'),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: onClose, child: const Text('Done')),
      ],
    );
  }
}
