import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';

/// Logs a whole bench session at once.
///
/// A practical uses six reagents and three beakers. Logging those one at a time
/// is nine panels and nine confirmations; here it is nine numbers and one save,
/// which is also how the session is written down on paper.
void openSession(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SessionScreen()),
  );
}

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  /// Only the items that actually moved, keyed by id. Absent means "untouched",
  /// which is different from zero and never written.
  final Map<String, double> _amounts = {};
  final _search = TextEditingController();
  bool _saving = false;
  ItemKind _kind = ItemKind.chemical;
  late DateTime _date = DateTime.now();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ItemView> _items(InventoryState state) {
    final query = _search.text.trim().toLowerCase();
    final views = _kind == ItemKind.chemical
        ? state.chemicals.map(ItemView.fromChemical)
        : state.apparatus.map(ItemView.fromApparatus);
    return views
        .where(
          (item) =>
              query.isEmpty ||
              '${item.name} ${item.subtitle}'.toLowerCase().contains(query),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _bump(ItemView item, double delta) {
    final next = (_amounts[item.id] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _amounts.remove(item.id);
      } else {
        _amounts[item.id] = next;
      }
    });
  }

  Future<void> _save() async {
    if (_amounts.isEmpty || _saving) return;
    setState(() => _saving = true);
    final state = ref.read(inventoryProvider);
    final views = <String, ItemView>{
      for (final item in [
        ...state.chemicals.map(ItemView.fromChemical),
        ...state.apparatus.map(ItemView.fromApparatus),
      ])
        item.id: item,
    };
    var saved = 0;
    final savedIds = <String>[];
    final failures = <String>[];
    for (final entry in _amounts.entries) {
      final item = views[entry.key];
      if (item == null) {
        failures.add('An item is no longer on the shelf.');
        continue;
      }
      try {
        await ref
            .read(inventoryProvider.notifier)
            .applyAction(
              itemId: item.id,
              itemType: item.kind,
              action: item.isChemical
                  ? InventoryAction.consume
                  : InventoryAction.breakage,
              amount: entry.value,
              note: 'Session',
              date: _date,
            );
        saved++;
        savedIds.add(entry.key);
      } catch (error) {
        failures.add('${item.name}: ${friendlyError(error)}');
      }
    }
    if (!mounted) return;
    setState(() {
      for (final id in savedIds) {
        _amounts.remove(id);
      }
      _saving = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    if (failures.isEmpty) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Logged $saved items')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$saved saved; ${failures.length} could not be logged. '
            'Only the remaining items will be retried. ${failures.first}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final items = _items(state);
    final count = _amounts.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Log a session'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                helpText: 'When was the session?',
              );
              if (picked != null && mounted) setState(() => _date = picked);
            },
            icon: const Icon(Icons.event_outlined, size: 16),
            label: Text(
              _date.day == DateTime.now().day &&
                      _date.month == DateTime.now().month
                  ? 'Today'
                  : '${_date.day}/${_date.month}',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 0
                      ? 'Tap + on what you used'
                      : '$count item${count == 1 ? '' : 's'} ready',
                  style: context.itemName.copyWith(fontSize: 19),
                ),
                const SizedBox(height: 2),
                Text(
                  'Only the items you count are saved; everything else is left '
                  'exactly as it is.',
                  style: context.aside.copyWith(fontSize: LabType.small),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _KindTab(
                      label: 'CHEMICALS',
                      selected: _kind == ItemKind.chemical,
                      onTap: () => setState(() => _kind = ItemKind.chemical),
                    ),
                    const SizedBox(width: 7),
                    _KindTab(
                      label: 'APPARATUS',
                      selected: _kind == ItemKind.apparatus,
                      onTap: () => setState(() => _kind = ItemKind.apparatus),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: LabType.small),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Find an item',
                    prefixIcon: Icon(Icons.search, size: 17, color: lab.soft),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = items[index];
                final amount = _amounts[item.id] ?? 0;
                final selected = amount > 0;
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: selected ? lab.wash(lab.clay) : null,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: selected ? lab.wash(lab.clay, .4) : lab.hair,
                    ),
                  ),
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
                              style: context.itemName.copyWith(
                                fontSize: LabType.small + 1,
                              ),
                            ),
                            Text(
                              '${formatQuantity(item.quantity)} ${item.unit} '
                              'on shelf',
                              style: context.formula.copyWith(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove one ${item.unit} from ${item.name}',
                        onPressed: selected && !_saving ? () => _bump(item, -1) : null,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      SizedBox(
                        width: 54,
                        child: Text(
                          selected ? formatQuantity(amount) : '—',
                          textAlign: TextAlign.center,
                          style: context.figure.copyWith(
                            fontSize: LabType.small + 1,
                            color: selected ? lab.clay : lab.soft,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add one ${item.unit} to ${item.name}',
                        onPressed: _saving ? null : () => _bump(item, 1),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _amounts.isEmpty || _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _amounts.isEmpty
                              ? 'Nothing counted yet'
                              : 'Save $count '
                                    'item${count == 1 ? '' : 's'}',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindTab extends StatelessWidget {
  const _KindTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? lab.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? lab.ink : lab.hair),
            ),
            child: Text(
              label,
              style: context.label.copyWith(
                fontSize: LabType.micro,
                color: selected ? lab.bone : lab.soft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
