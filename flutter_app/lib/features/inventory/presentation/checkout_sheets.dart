import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';
import 'inventory_sheets.dart';

/// Lends pieces of an apparatus to a person (GEAR-02).
Future<void> showCheckoutSheet(BuildContext context, String apparatusId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NotebookSheetFrame(
        child: _CheckoutForm(apparatusId: apparatusId),
      ),
    );

/// Takes pieces back from an open loan.
Future<void> showReturnSheet(BuildContext context, String checkoutId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NotebookSheetFrame(
        child: _ReturnForm(checkoutId: checkoutId),
      ),
    );

/// Short due-date copy such as "due in 3 days" or "overdue by 2 days".
String dueCaption(DateTime? dueAt, {DateTime? now}) {
  if (dueAt == null) return '';
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final days = due.difference(today).inDays;
  if (days == 0) return 'due today';
  if (days == 1) return 'due tomorrow';
  if (days > 1) return 'due in $days days';
  if (days == -1) return 'overdue by 1 day';
  return 'overdue by ${-days} days';
}

/// Availability line, open loans and recent returns for the item sheet.
class CheckoutSection extends ConsumerWidget {
  const CheckoutSection({super.key, required this.apparatus});

  final Apparatus apparatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inventoryProvider);
    final open = state.openCheckoutsFor(apparatus.id);
    final out = state.checkedOutCount(apparatus.id);
    final available = state.availableCount(apparatus);
    final past = [
      for (final checkout in state.checkouts)
        if (checkout.apparatusId == apparatus.id && !checkout.isOpen) checkout,
    ].take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        PageHeading(
          'checkouts',
          trailing: TextButton.icon(
            key: const Key('checkout-open'),
            onPressed: available > 0
                ? () => showCheckoutSheet(context, apparatus.id)
                : null,
            icon: const Icon(Icons.outbox_outlined, size: 18),
            label: const Text('Check out'),
          ),
        ),
        Text(
          out > 0
              ? '${formatQuantity(available)} of ${formatQuantity(apparatus.quantity)} '
                    'available · ${formatQuantity(out)} checked out'
              : apparatus.quantity <= 0
              ? 'Nothing in stock to lend.'
              : 'All ${formatQuantity(apparatus.quantity)} pieces are in.',
          key: const Key('checkout-availability'),
          style: TextStyle(color: context.mutedInkColor, fontSize: 13),
        ),
        for (final checkout in open)
          ListTile(
            key: Key('checkout-${checkout.id}'),
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: checkout.isOverdue()
                  ? context.marginRedColor.withValues(alpha: .15)
                  : null,
              child: Icon(
                checkout.isOverdue()
                    ? Icons.alarm_outlined
                    : Icons.person_outline,
                color: checkout.isOverdue() ? context.marginRedColor : null,
              ),
            ),
            title: Text(
              '${checkout.person.isEmpty ? 'someone' : checkout.person} · '
              '${formatQuantity(checkout.outstanding)} pcs',
            ),
            subtitle: Text(
              [
                'since ${relativeTime(checkout.checkedOutAt)}',
                if (checkout.dueAt != null) dueCaption(checkout.dueAt),
                if (checkout.note.isNotEmpty) checkout.note,
              ].join(' · '),
              style: checkout.isOverdue()
                  ? TextStyle(color: context.marginRedColor)
                  : null,
            ),
            trailing: TextButton(
              key: Key('return-${checkout.id}'),
              onPressed: () => showReturnSheet(context, checkout.id),
              child: const Text('return'),
            ),
          ),
        if (past.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'recently returned',
            style: TextStyle(
              fontFamily: 'Caveat',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.mutedInkColor,
            ),
          ),
          for (final checkout in past)
            ListTile(
              key: Key('checkout-past-${checkout.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.assignment_return_outlined,
                color: context.mutedInkColor,
              ),
              title: Text(
                '${checkout.person.isEmpty ? 'someone' : checkout.person} · '
                '${formatQuantity(checkout.quantity)} pcs',
              ),
              subtitle: Text(
                'returned ${relativeTime(checkout.returnedAt ?? checkout.checkedOutAt)}'
                '${checkout.returnNote.isEmpty ? '' : ' · ${checkout.returnNote}'}',
              ),
            ),
        ],
      ],
    );
  }
}

class _CheckoutForm extends ConsumerStatefulWidget {
  const _CheckoutForm({required this.apparatusId});

  final String apparatusId;

  @override
  ConsumerState<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends ConsumerState<_CheckoutForm> {
  final _formKey = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _due = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _person.dispose();
    _quantity.dispose();
    _due.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final item = state.apparatus
        .where((entry) => entry.id == widget.apparatusId)
        .firstOrNull;
    if (item == null) {
      return const EmptyNotebookState(
        icon: Icons.search_off,
        title: 'item not found',
        message: 'It may have been removed on another device.',
      );
    }
    final available = state.availableCount(item);
    final people = <String>{
      for (final checkout in state.checkouts)
        if (checkout.person.trim().isNotEmpty) checkout.person.trim(),
    }.take(6).toList();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading('check out ${item.name}'),
          Text(
            '${formatQuantity(available)} of ${formatQuantity(item.quantity)} '
            'available',
            style: TextStyle(color: context.mutedInkColor),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('checkout-person'),
            controller: _person,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Who is taking it?',
              hintText: 'Name, group or bench',
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Required' : null,
          ),
          if (people.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final person in people)
                  ActionChip(
                    key: Key('checkout-person-$person'),
                    label: Text(person),
                    onPressed: () => setState(() => _person.text = person),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('checkout-quantity'),
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Pieces',
                    suffixText: 'pcs',
                  ),
                  validator: (value) {
                    final number = double.tryParse((value ?? '').trim());
                    if (number == null || number <= 0) return 'At least 1';
                    if (number != number.roundToDouble()) {
                      return 'Whole pieces only';
                    }
                    if (number > available) {
                      return 'Only ${formatQuantity(available)} available';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('checkout-due'),
                  controller: _due,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: 'Due back',
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: IconButton(
                      tooltip: 'Pick due date',
                      onPressed: _pickDue,
                      icon: const Icon(Icons.event_outlined),
                    ),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    final valid =
                        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
                        parseDateOnly(text) != null;
                    return valid ? null : 'Use YYYY-MM-DD';
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final (label, days) in const [
                ('tomorrow', 1),
                ('1 week', 7),
                ('2 weeks', 14),
                ('1 month', 30),
              ])
                ActionChip(
                  key: Key('checkout-due-$days'),
                  label: Text(label),
                  onPressed: () => setState(() {
                    final now = DateTime.now();
                    _due.text = formatDateOnly(
                      DateTime(now.year, now.month, now.day + days),
                    );
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('checkout-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Purpose, room, condition on hand-over…',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('checkout-submit'),
            onPressed: _saving || available <= 0 ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.outbox_outlined),
            label: Text(
              _saving
                  ? 'Saving…'
                  : available <= 0
                  ? 'Nothing available'
                  : 'Check out',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var initial = parseDateOnly(_due.text) ?? today.add(const Duration(days: 7));
    if (initial.isBefore(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
      helpText: 'Due back',
    );
    if (picked != null) _due.text = formatDateOnly(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final due = parseDateOnly(_due.text);
      await ref
          .read(inventoryProvider.notifier)
          .checkoutApparatus(
            apparatusId: widget.apparatusId,
            quantity: double.parse(_quantity.text.trim()),
            person: _person.text,
            note: _note.text,
            // Due at the end of the chosen day, local time.
            dueAt: due == null
                ? null
                : DateTime(due.year, due.month, due.day, 23, 59),
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_quantity.text.trim()} pcs checked out to ${_person.text.trim()}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}

class _ReturnForm extends ConsumerStatefulWidget {
  const _ReturnForm({required this.checkoutId});

  final String checkoutId;

  @override
  ConsumerState<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends ConsumerState<_ReturnForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final checkout = ref
        .read(inventoryProvider)
        .checkouts
        .where((entry) => entry.id == widget.checkoutId)
        .firstOrNull;
    _quantity = TextEditingController(
      text: checkout == null ? '1' : formatQuantity(checkout.outstanding),
    );
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final checkout = state.checkouts
        .where((entry) => entry.id == widget.checkoutId)
        .firstOrNull;
    if (checkout == null || !checkout.isOpen) {
      return const EmptyNotebookState(
        icon: Icons.assignment_turned_in_outlined,
        title: 'already returned',
        message: 'This loan is closed.',
      );
    }
    final item = state.apparatus
        .where((entry) => entry.id == checkout.apparatusId)
        .firstOrNull;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading('return ${item?.name ?? 'apparatus'}'),
          Text(
            '${checkout.person.isEmpty ? 'Someone' : checkout.person} has '
            '${formatQuantity(checkout.outstanding)} pcs since '
            '${relativeTime(checkout.checkedOutAt)}'
            '${checkout.dueAt == null ? '' : ' · ${dueCaption(checkout.dueAt)}'}',
            style: TextStyle(color: context.mutedInkColor),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('return-quantity'),
            controller: _quantity,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pieces coming back',
              suffixText: 'pcs',
            ),
            validator: (value) {
              final number = double.tryParse((value ?? '').trim());
              if (number == null || number <= 0) return 'At least 1';
              if (number != number.roundToDouble()) return 'Whole pieces only';
              if (number > checkout.outstanding) {
                return 'Only ${formatQuantity(checkout.outstanding)} out';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('return-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Condition on return, missing parts…',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('return-submit'),
            onPressed: _saving ? null : () => _save(checkout),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assignment_return_outlined),
            label: Text(_saving ? 'Saving…' : 'Mark returned'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(ApparatusCheckout checkout) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final quantity = double.parse(_quantity.text.trim());
      final updated = await ref
          .read(inventoryProvider.notifier)
          .returnApparatus(
            checkoutId: checkout.id,
            quantity: quantity,
            note: _note.text,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updated.isOpen
                ? '${formatQuantity(quantity)} pcs back · '
                      '${formatQuantity(updated.outstanding)} still out'
                : 'Loan closed · ${formatQuantity(quantity)} pcs back',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}
