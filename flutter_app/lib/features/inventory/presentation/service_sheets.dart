import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';
import 'checkout_sheets.dart' show dueCaption;
import 'chemical_details.dart' show expiryColor;
import 'inventory_sheets.dart';

/// Schedules maintenance or calibration for an apparatus (GEAR-03).
Future<void> showScheduleServiceSheet(
  BuildContext context,
  String apparatusId, {
  ServiceKind kind = ServiceKind.maintenance,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => NotebookSheetFrame(
    child: _ScheduleForm(apparatusId: apparatusId, initialKind: kind),
  ),
);

/// Records a scheduled task as done.
Future<void> showCompleteServiceSheet(BuildContext context, String serviceId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          NotebookSheetFrame(child: _CompleteForm(serviceId: serviceId)),
    );

/// "due in 3 days" style copy for a task, or "no due date".
String serviceDueCaption(ApparatusService service, {DateTime? now}) {
  final due = service.dueAt;
  if (due == null) return 'no due date';
  return dueCaption(due, now: now);
}

/// Quick interval chips shared by both sheets.
const _intervals = [
  ('1 month', 30),
  ('3 months', 91),
  ('6 months', 182),
  ('1 year', 365),
];

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String? _validateOptionalDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final valid =
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
      parseDateOnly(text) != null;
  return valid ? null : 'Use YYYY-MM-DD';
}

/// Open tasks, completed history and the schedule button for the item sheet.
class ServiceSection extends ConsumerWidget {
  const ServiceSection({super.key, required this.apparatus});

  final Apparatus apparatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inventoryProvider);
    final tasks = state.servicesFor(apparatus.id);
    final open = tasks.where((task) => task.isOpen).toList();
    final done = tasks.where((task) => task.isDone).take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        PageHeading(
          'maintenance & calibration',
          fontSize: 30,
          trailing: TextButton.icon(
            key: const Key('service-schedule-open'),
            onPressed: () => showScheduleServiceSheet(context, apparatus.id),
            icon: const Icon(Icons.build_outlined, size: 18),
            label: const Text('Schedule'),
          ),
        ),
        if (open.isEmpty)
          Text(
            done.isEmpty
                ? 'Nothing scheduled. Add a calibration or service date so '
                      'the shelf can warn you.'
                : 'Nothing scheduled.',
            key: const Key('service-empty'),
            style: TextStyle(color: context.mutedInkColor, fontSize: 13),
          ),
        for (final task in open)
          Builder(
            builder: (context) {
              final dueState = task.dueState();
              final color = expiryColor(context, dueState);
              final urgent =
                  dueState == ExpiryState.expired ||
                  dueState == ExpiryState.expiringSoon;
              return ListTile(
                key: Key('service-${task.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: urgent ? color.withValues(alpha: .15) : null,
                  child: Icon(
                    task.kind == ServiceKind.calibration
                        ? Icons.straighten_outlined
                        : Icons.build_outlined,
                    color: urgent ? color : null,
                  ),
                ),
                title: Text(task.displayTitle),
                subtitle: Text(
                  [
                    if (task.title.isNotEmpty) task.kind.label.toLowerCase(),
                    serviceDueCaption(task),
                    if (task.note.isNotEmpty) task.note,
                  ].join(' · '),
                  style: urgent ? TextStyle(color: color) : null,
                ),
                trailing: TextButton(
                  key: Key('service-done-${task.id}'),
                  onPressed: () => showCompleteServiceSheet(context, task.id),
                  child: const Text('done'),
                ),
              );
            },
          ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'completed',
            style: TextStyle(
              fontFamily: 'Caveat',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.mutedInkColor,
            ),
          ),
          for (final task in done)
            ListTile(
              key: Key('service-past-${task.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.task_alt_outlined,
                color: task.result == 'fail'
                    ? context.marginRedColor
                    : context.healthyColor,
              ),
              title: Text(
                '${task.displayTitle}'
                '${task.result.isEmpty ? '' : ' · ${task.result}'}',
              ),
              subtitle: Text(
                [
                  'done ${relativeTime(task.completedAt ?? task.createdAt)}',
                  if (task.performedBy.isNotEmpty) 'by ${task.performedBy}',
                  if (task.note.isNotEmpty) task.note,
                ].join(' · '),
              ),
            ),
        ],
      ],
    );
  }
}

class _ScheduleForm extends ConsumerStatefulWidget {
  const _ScheduleForm({required this.apparatusId, required this.initialKind});

  final String apparatusId;
  final ServiceKind initialKind;

  @override
  ConsumerState<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends ConsumerState<_ScheduleForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _due = TextEditingController();
  final _note = TextEditingController();
  late ServiceKind _kind = widget.initialKind;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _due.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ref
        .watch(inventoryProvider)
        .apparatus
        .where((entry) => entry.id == widget.apparatusId)
        .firstOrNull;
    if (item == null) {
      return const EmptyNotebookState(
        icon: Icons.search_off,
        title: 'item not found',
        message: 'It may have been removed on another device.',
      );
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading('schedule for ${item.name}', fontSize: 30),
          const SizedBox(height: 8),
          SegmentedButton<ServiceKind>(
            segments: [
              for (final kind in ServiceKind.values)
                ButtonSegment(
                  value: kind,
                  label: Text(
                    kind.label,
                    key: Key('service-kind-${kind.value}'),
                  ),
                  icon: Icon(
                    kind == ServiceKind.calibration
                        ? Icons.straighten_outlined
                        : Icons.build_outlined,
                  ),
                ),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Task',
              hintText: _kind == ServiceKind.calibration
                  ? 'e.g. Annual calibration'
                  : 'e.g. Replace tubing',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-due'),
            controller: _due,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: 'Due',
              hintText: 'YYYY-MM-DD',
              suffixIcon: IconButton(
                tooltip: 'Pick due date',
                onPressed: () => _pickDate(_due),
                icon: const Icon(Icons.event_outlined),
              ),
            ),
            validator: _validateOptionalDate,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final (label, days) in _intervals)
                ActionChip(
                  key: Key('service-due-$days'),
                  label: Text(label),
                  onPressed: () => setState(
                    () => _due.text = formatDateOnly(
                      _today().add(Duration(days: days)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Standard, tolerance, vendor…',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('service-submit'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.event_available_outlined),
            label: Text(_saving ? 'Saving…' : 'Schedule ${_kind.label}'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final today = _today();
    var initial =
        parseDateOnly(controller.text) ?? today.add(const Duration(days: 30));
    if (initial.isBefore(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) controller.text = formatDateOnly(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final due = parseDateOnly(_due.text);
      await ref
          .read(inventoryProvider.notifier)
          .scheduleService(
            apparatusId: widget.apparatusId,
            kind: _kind,
            title: _title.text,
            note: _note.text,
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
            due == null
                ? '${_kind.label} scheduled'
                : '${_kind.label} due ${formatDateOnly(due)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}

class _CompleteForm extends ConsumerStatefulWidget {
  const _CompleteForm({required this.serviceId});

  final String serviceId;

  @override
  ConsumerState<_CompleteForm> createState() => _CompleteFormState();
}

class _CompleteFormState extends ConsumerState<_CompleteForm> {
  final _formKey = GlobalKey<FormState>();
  final _date = TextEditingController(text: formatDateOnly(DateTime.now()));
  final _person = TextEditingController();
  final _result = TextEditingController();
  final _note = TextEditingController();
  final _next = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _date.dispose();
    _person.dispose();
    _result.dispose();
    _note.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final task = state.services
        .where((entry) => entry.id == widget.serviceId)
        .firstOrNull;
    if (task == null || task.isDone) {
      return const EmptyNotebookState(
        icon: Icons.task_alt_outlined,
        title: 'already done',
        message: 'This task is completed.',
      );
    }
    final item = state.apparatus
        .where((entry) => entry.id == task.apparatusId)
        .firstOrNull;
    final people = <String>{
      for (final service in state.services)
        if (service.performedBy.trim().isNotEmpty) service.performedBy.trim(),
    }.take(6).toList();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading('${task.displayTitle} done', fontSize: 30),
          Text(
            '${item?.name ?? 'Apparatus'} · ${serviceDueCaption(task)}',
            style: TextStyle(color: context.mutedInkColor),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-done-date'),
            controller: _date,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: 'Done on',
              hintText: 'YYYY-MM-DD',
              suffixIcon: IconButton(
                tooltip: 'Pick date',
                onPressed: _pickDone,
                icon: const Icon(Icons.event_outlined),
              ),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              final date = parseDateOnly(text);
              if (text.isEmpty || date == null) return 'Use YYYY-MM-DD';
              if (date.isAfter(_today())) return 'Cannot be in the future';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-performed-by'),
            controller: _person,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Performed by',
              hintText: 'Technician, vendor or you',
            ),
          ),
          if (people.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final person in people)
                  ActionChip(
                    key: Key('service-person-$person'),
                    label: Text(person),
                    onPressed: () => setState(() => _person.text = person),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-result'),
            controller: _result,
            decoration: const InputDecoration(
              labelText: 'Result',
              hintText: 'pass, adjusted, fail…',
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final result in serviceResults)
                ChoiceChip(
                  key: Key('service-result-$result'),
                  label: Text(result),
                  selected: _result.text.trim() == result,
                  onSelected: (_) => setState(() => _result.text = result),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-complete-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Readings, parts replaced, certificate number…',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('service-next'),
            controller: _next,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: 'Schedule next (optional)',
              hintText: 'YYYY-MM-DD',
              suffixIcon: IconButton(
                tooltip: 'Pick next date',
                onPressed: _pickNext,
                icon: const Icon(Icons.event_repeat_outlined),
              ),
            ),
            validator: (value) {
              final error = _validateOptionalDate(value);
              if (error != null) return error;
              final date = parseDateOnly(value);
              if (date != null && date.isBefore(_today())) {
                return 'Next date must be ahead';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              ActionChip(
                key: const Key('service-next-none'),
                label: const Text('no repeat'),
                onPressed: () => setState(_next.clear),
              ),
              for (final (label, days) in _intervals)
                ActionChip(
                  key: Key('service-next-$days'),
                  label: Text(label),
                  onPressed: () => setState(
                    () => _next.text = formatDateOnly(
                      _today().add(Duration(days: days)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('service-complete-submit'),
            onPressed: _saving ? null : () => _save(task),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.task_alt_outlined),
            label: Text(_saving ? 'Saving…' : 'Mark done'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDone() async {
    final today = _today();
    var initial = parseDateOnly(_date.text) ?? today;
    if (initial.isAfter(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(today.year - 10),
      lastDate: today,
    );
    if (picked != null) _date.text = formatDateOnly(picked);
  }

  Future<void> _pickNext() async {
    final today = _today();
    var initial =
        parseDateOnly(_next.text) ?? today.add(const Duration(days: 365));
    if (initial.isBefore(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) _next.text = formatDateOnly(picked);
  }

  Future<void> _save(ApparatusService task) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final done = parseDateOnly(_date.text)!;
      final now = DateTime.now();
      final isToday = done == _today();
      final next = parseDateOnly(_next.text);
      await ref
          .read(inventoryProvider.notifier)
          .completeService(
            serviceId: task.id,
            // Keep the clock time when completed today; noon otherwise.
            completedAt: isToday
                ? now
                : DateTime(done.year, done.month, done.day, 12),
            performedBy: _person.text,
            result: _result.text,
            note: _note.text,
            nextDueAt: next == null
                ? null
                : DateTime(next.year, next.month, next.day, 23, 59),
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            next == null
                ? '${task.displayTitle} marked done'
                : '${task.displayTitle} done · next ${formatDateOnly(next)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}
