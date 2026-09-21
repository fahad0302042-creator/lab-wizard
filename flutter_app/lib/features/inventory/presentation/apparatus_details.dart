import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';
import 'chemical_details.dart' show expiryCaption, expiryColor;

/// Holds the optional apparatus metadata fields (GEAR-01) for the add and
/// edit forms. The owning form disposes it.
class ApparatusDetailsController extends ChangeNotifier {
  ApparatusDetailsController([
    ApparatusDetails initial = const ApparatusDetails(),
  ]) : serialNumber = TextEditingController(text: initial.serialNumber ?? ''),
       assignedTo = TextEditingController(text: initial.assignedTo ?? ''),
       location = TextEditingController(text: initial.location ?? ''),
       purchaseDate = TextEditingController(
         text: initial.purchaseDate == null
             ? ''
             : formatDateOnly(initial.purchaseDate!),
       ),
       warrantyUntil = TextEditingController(
         text: initial.warrantyUntil == null
             ? ''
             : formatDateOnly(initial.warrantyUntil!),
       ),
       _condition = ApparatusCondition.fromLabel(initial.condition),
       _expanded = !initial.isEmpty {
    for (final controller in textControllers) {
      controller.addListener(notifyListeners);
    }
  }

  final TextEditingController serialNumber;
  final TextEditingController assignedTo;
  final TextEditingController location;
  final TextEditingController purchaseDate;
  final TextEditingController warrantyUntil;
  ApparatusCondition? _condition;
  bool _expanded;

  List<TextEditingController> get textControllers => [
    serialNumber,
    assignedTo,
    location,
    purchaseDate,
    warrantyUntil,
  ];

  bool get expanded => _expanded;

  set expanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  ApparatusCondition? get condition => _condition;

  set condition(ApparatusCondition? value) {
    if (_condition == value) return;
    _condition = value;
    notifyListeners();
  }

  ApparatusDetails get value => ApparatusDetails(
    serialNumber: serialNumber.text.trim(),
    condition: _condition?.label,
    assignedTo: assignedTo.text.trim(),
    location: location.text.trim(),
    purchaseDate: parseDateOnly(purchaseDate.text),
    warrantyUntil: parseDateOnly(warrantyUntil.text),
  );

  /// First problem with the typed details, or null when they can be saved.
  String? validate() =>
      validateDate(purchaseDate.text) ?? validateDate(warrantyUntil.text);

  static String? validateDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final valid =
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
        parseDateOnly(text) != null;
    return valid ? null : 'Use the YYYY-MM-DD format';
  }

  @override
  void dispose() {
    for (final controller in textControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

/// Collapsible "more details" section for apparatus forms.
class ApparatusDetailsFields extends StatelessWidget {
  const ApparatusDetailsFields({super.key, required this.controller});

  final ApparatusDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final filled = !controller.value.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const Key('apparatus-details-toggle'),
              onTap: () => controller.expanded = !controller.expanded,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      controller.expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: context.mutedInkColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'more details',
                        style: TextStyle(
                          fontFamily: 'Caveat',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: context.inkColor,
                        ),
                      ),
                    ),
                    Text(
                      filled
                          ? 'serial · condition · assignee · dates'
                          : 'optional',
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Visibility(
              visible: controller.expanded,
              maintainState: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  TextFormField(
                    key: const Key('gear-serial'),
                    controller: controller.serialNumber,
                    decoration: const InputDecoration(
                      labelText: 'Serial number / asset tag',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('gear-condition'),
                    initialValue: controller.condition?.name ?? '',
                    decoration: const InputDecoration(labelText: 'Condition'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('not recorded'),
                      ),
                      for (final condition in ApparatusCondition.values)
                        DropdownMenuItem(
                          key: Key('gear-condition-${condition.name}'),
                          value: condition.name,
                          child: Text(condition.label),
                        ),
                    ],
                    onChanged: (value) => controller.condition =
                        value == null || value.isEmpty
                        ? null
                        : ApparatusCondition.values.byName(value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('gear-assigned'),
                    controller: controller.assignedTo,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Assigned to',
                      hintText: 'Person or bench',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('gear-location'),
                    controller: controller.location,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Storage location',
                      hintText: 'Bench 3, store room',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DateField(
                          key: const Key('gear-purchase'),
                          controller: controller.purchaseDate,
                          label: 'Purchased',
                          helpText: 'Purchase date',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DateField(
                          key: const Key('gear-warranty'),
                          controller: controller.warrantyUntil,
                          label: 'Warranty until',
                          helpText: 'Warranty end',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.helpText,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String helpText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        suffixIcon: IconButton(
          tooltip: helpText,
          onPressed: () => _pick(context),
          icon: const Icon(Icons.event_outlined),
        ),
      ),
      validator: ApparatusDetailsController.validateDate,
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDateOnly(controller.text) ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 30),
      helpText: helpText,
    );
    if (picked != null) controller.text = formatDateOnly(picked);
  }
}

Color conditionColor(BuildContext context, ApparatusCondition condition) =>
    switch (condition) {
      ApparatusCondition.good => context.healthyColor,
      ApparatusCondition.fair => context.lowColor,
      ApparatusCondition.needsRepair => context.marginRedColor,
      ApparatusCondition.retired => context.mutedInkColor,
    };

IconData conditionIcon(ApparatusCondition condition) => switch (condition) {
  ApparatusCondition.good => Icons.check_circle_outline,
  ApparatusCondition.fair => Icons.info_outline,
  ApparatusCondition.needsRepair => Icons.build_outlined,
  ApparatusCondition.retired => Icons.do_not_disturb_on_outlined,
};

/// Small condition / assignee marker for shelf rows. Hidden when the item is
/// in good condition and unassigned.
class ApparatusMarks extends StatelessWidget {
  const ApparatusMarks(this.item, {super.key, this.compact = false});

  final Apparatus item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final condition = item.conditionValue;
    final showCondition =
        condition != null && condition != ApparatusCondition.good;
    final assigned = (item.assignedTo ?? '').isNotEmpty;
    final warranty = item.warrantyState();
    final warrantyWarning =
        warranty == ExpiryState.expired || warranty == ExpiryState.expiringSoon;
    if (!showCondition && !assigned && !warrantyWarning) {
      return const SizedBox.shrink();
    }
    final conditionMark = condition != null && showCondition
        ? _Mark(
            key: const Key('mark-condition'),
            icon: conditionIcon(condition),
            text: condition.label,
            color: conditionColor(context, condition),
            fontSize: compact ? 10.0 : 11.0,
          )
        : null;
    final size = compact ? 10.0 : 11.0;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 2 : 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (conditionMark != null) conditionMark,
          if (assigned)
            _Mark(
              key: const Key('mark-assigned'),
              icon: Icons.person_outline,
              text: item.assignedTo!,
              color: context.mutedInkColor,
              fontSize: size,
            ),
          if (warrantyWarning)
            _Mark(
              key: const Key('mark-warranty'),
              icon: Icons.verified_outlined,
              text: warranty == ExpiryState.expired
                  ? 'warranty ended'
                  : 'warranty ending',
              color: expiryColor(context, warranty),
              fontSize: size,
            ),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({
    required this.icon,
    required this.text,
    required this.color,
    required this.fontSize,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: fontSize + 3, color: color),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Metadata block for the apparatus item sheet.
class ApparatusDetailsSummary extends StatelessWidget {
  const ApparatusDetailsSummary(this.item, {super.key});

  final Apparatus item;

  @override
  Widget build(BuildContext context) {
    if (!item.hasMetadata) return const SizedBox.shrink();
    final condition = item.conditionValue;
    final warranty = item.warrantyState();
    final rows = <(String, String)>[
      if ((item.serialNumber ?? '').isNotEmpty) ('serial', item.serialNumber!),
      if ((item.condition ?? '').isNotEmpty)
        ('condition', condition?.label ?? item.condition!),
      if ((item.assignedTo ?? '').isNotEmpty) ('assigned to', item.assignedTo!),
      if ((item.location ?? '').isNotEmpty) ('location', item.location!),
      if (item.purchaseDate != null)
        ('purchased', formatDateOnly(item.purchaseDate!)),
      if (item.warrantyUntil != null)
        (
          'warranty',
          '${formatDateOnly(item.warrantyUntil!)} · '
              '${expiryCaption(item.warrantyUntil).replaceFirst('expires', 'ends').replaceFirst('expired', 'ended')}',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const PageHeading('details', trailing: SizedBox.shrink()),
        NotebookCard(
          key: const Key('apparatus-details-summary'),
          accent: condition == ApparatusCondition.needsRepair
              ? context.marginRedColor
              : warranty == ExpiryState.expired ||
                    warranty == ExpiryState.expiringSoon
              ? context.lowColor
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 108,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: context.mutedInkColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            color: label == 'condition' && condition != null
                                ? conditionColor(context, condition)
                                : label == 'warranty' &&
                                      warranty != ExpiryState.ok
                                ? expiryColor(context, warranty)
                                : context.inkColor,
                            fontWeight:
                                (label == 'condition' &&
                                        condition != null &&
                                        condition != ApparatusCondition.good) ||
                                    (label == 'warranty' &&
                                        warranty != ExpiryState.ok)
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
