import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/models.dart';

/// Holds the optional chemical metadata fields (DATA-01) for the add and
/// edit forms. The owning form disposes it.
class ChemicalDetailsController extends ChangeNotifier {
  ChemicalDetailsController([ChemicalDetails initial = const ChemicalDetails()])
    : supplier = TextEditingController(text: initial.supplier ?? ''),
      casNumber = TextEditingController(text: initial.casNumber ?? ''),
      concentration = TextEditingController(text: initial.concentration ?? ''),
      location = TextEditingController(text: initial.location ?? ''),
      expiry = TextEditingController(
        text: initial.expiryDate == null
            ? ''
            : formatDateOnly(initial.expiryDate!),
      ),
      _hazards = {...parseHazardList(initial.hazardClasses)},
      _expanded = !initial.isEmpty {
    for (final controller in textControllers) {
      controller.addListener(notifyListeners);
    }
  }

  final TextEditingController supplier;
  final TextEditingController casNumber;
  final TextEditingController concentration;
  final TextEditingController location;

  /// Calendar date typed as `YYYY-MM-DD` or picked from the date picker.
  final TextEditingController expiry;

  final Set<String> _hazards;
  bool _expanded;

  List<TextEditingController> get textControllers => [
    supplier,
    casNumber,
    concentration,
    location,
    expiry,
  ];

  bool get expanded => _expanded;

  set expanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  bool hasHazard(HazardClass hazard) => _hazards.contains(hazard.code);

  void toggleHazard(HazardClass hazard, bool selected) {
    if (selected) {
      _hazards.add(hazard.code);
    } else {
      _hazards.remove(hazard.code);
    }
    notifyListeners();
  }

  ChemicalDetails get value => ChemicalDetails(
    supplier: supplier.text.trim(),
    casNumber: casNumber.text.trim(),
    concentration: concentration.text.trim(),
    location: location.text.trim(),
    expiryDate: parseDateOnly(expiry.text),
    hazardClasses: [
      for (final hazard in HazardClass.values)
        if (_hazards.contains(hazard.code)) hazard.code,
    ],
  );

  /// First problem with the typed details, or null when they can be saved.
  String? validate() =>
      validateCas(casNumber.text) ?? validateExpiry(expiry.text);

  static String? validateCas(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || isValidCasNumber(text)) return null;
    return 'Not a valid CAS number (example: 7732-18-5)';
  }

  static String? validateExpiry(String? value) {
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

/// Collapsible "more details" section for chemical forms.
class ChemicalDetailsFields extends StatelessWidget {
  const ChemicalDetailsFields({super.key, required this.controller});

  final ChemicalDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final filled = !controller.value.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailsToggle(
              key: const Key('chemical-details-toggle'),
              expanded: controller.expanded,
              summary: filled
                  ? 'supplier · CAS · expiry · hazards'
                  : 'optional',
              onTap: () => controller.expanded = !controller.expanded,
            ),
            // The fields stay in the tree while collapsed so validators run.
            Visibility(
              visible: controller.expanded,
              maintainState: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  TextFormField(
                    key: const Key('detail-supplier'),
                    controller: controller.supplier,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('detail-cas'),
                          controller: controller.casNumber,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'CAS number',
                            hintText: '7732-18-5',
                          ),
                          validator: ChemicalDetailsController.validateCas,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('detail-concentration'),
                          controller: controller.concentration,
                          decoration: const InputDecoration(
                            labelText: 'Concentration',
                            hintText: '37% · 0.1 M',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('detail-location'),
                    controller: controller.location,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Storage location',
                      hintText: 'Cabinet B, shelf 2',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('detail-expiry'),
                    controller: controller.expiry,
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: 'Expiry date',
                      hintText: 'YYYY-MM-DD',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (controller.expiry.text.isNotEmpty)
                            IconButton(
                              tooltip: 'Clear expiry date',
                              onPressed: () => controller.expiry.clear(),
                              icon: const Icon(Icons.close),
                            ),
                          IconButton(
                            key: const Key('detail-expiry-picker'),
                            tooltip: 'Pick expiry date',
                            onPressed: () => _pickExpiry(context),
                            icon: const Icon(Icons.event_outlined),
                          ),
                        ],
                      ),
                    ),
                    validator: ChemicalDetailsController.validateExpiry,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'GHS hazards',
                    style: TextStyle(
                      color: context.mutedInkColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final hazard in HazardClass.values)
                        FilterChip(
                          key: Key('hazard-${hazard.code}'),
                          avatar: Icon(hazardIcon(hazard), size: 16),
                          label: Text(hazard.label),
                          tooltip: hazard.code,
                          selected: controller.hasHazard(hazard),
                          onSelected: (selected) =>
                              controller.toggleHazard(hazard, selected),
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

  Future<void> _pickExpiry(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDateOnly(controller.expiry.text) ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 50),
      helpText: 'Expiry date',
    );
    if (picked != null) controller.expiry.text = formatDateOnly(picked);
  }
}

/// Icon used for a GHS hazard class in chips and badges.
IconData hazardIcon(HazardClass hazard) => switch (hazard) {
  HazardClass.explosive => Icons.flare_outlined,
  HazardClass.flammable => Icons.local_fire_department_outlined,
  HazardClass.oxidizing => Icons.whatshot_outlined,
  HazardClass.compressedGas => Icons.propane_tank_outlined,
  HazardClass.corrosive => Icons.science_outlined,
  HazardClass.toxic => Icons.dangerous_outlined,
  HazardClass.irritant => Icons.priority_high,
  HazardClass.healthHazard => Icons.health_and_safety_outlined,
  HazardClass.environmental => Icons.eco_outlined,
};

/// Human copy for an expiry date, e.g. "expires in 12 days".
String expiryCaption(DateTime? expiryDate, {DateTime? now}) {
  if (expiryDate == null) return '';
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
  final days = expiry.difference(today).inDays;
  if (days == 0) return 'expires today';
  if (days == 1) return 'expires tomorrow';
  if (days == -1) return 'expired yesterday';
  if (days < 0) return 'expired ${-days} days ago';
  if (days > 60) {
    final months = (days / 30).round();
    return 'expires in about $months months';
  }
  return 'expires in $days days';
}

Color expiryColor(BuildContext context, ExpiryState state) => switch (state) {
  ExpiryState.expired => context.marginRedColor,
  ExpiryState.expiringSoon => context.lowColor,
  _ => context.healthyColor,
};

/// Compact expiry marker for shelf rows (DATA-02). Renders nothing when the
/// chemical has no expiry date or it is comfortably in the future.
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge(this.chemical, {super.key, this.compact = false});

  final Chemical chemical;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = chemical.expiryState();
    if (state == ExpiryState.none || state == ExpiryState.ok) {
      return const SizedBox.shrink();
    }
    final color = expiryColor(context, state);
    final text = state == ExpiryState.expired ? 'expired' : 'expiring';
    return Semantics(
      label: expiryCaption(chemical.expiryDate),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: .5)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 7,
            vertical: compact ? 1 : 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: compact ? 12 : 14,
                color: color,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row of small hazard icons for shelf rows.
class HazardStrip extends StatelessWidget {
  const HazardStrip(this.chemical, {super.key, this.size = 14});

  final Chemical chemical;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hazards = chemical.hazards;
    if (hazards.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'hazards: ${hazards.map((hazard) => hazard.label).join(', ')}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final hazard in hazards.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Tooltip(
                message: '${hazard.code} · ${hazard.label}',
                child: Icon(
                  hazardIcon(hazard),
                  size: size,
                  color: context.marginRedColor,
                ),
              ),
            ),
          if (hazards.length > 4)
            Text(
              '+${hazards.length - 4}',
              style: TextStyle(
                fontSize: size - 3,
                color: context.marginRedColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// Metadata block for the item detail sheet (DATA-02 presentation).
class ChemicalDetailsSummary extends StatelessWidget {
  const ChemicalDetailsSummary(this.chemical, {super.key});

  final Chemical chemical;

  @override
  Widget build(BuildContext context) {
    if (!chemical.hasMetadata) return const SizedBox.shrink();
    final expiryState = chemical.expiryState();
    final rows = <(String, String)>[
      if ((chemical.supplier ?? '').isNotEmpty)
        ('supplier', chemical.supplier!),
      if ((chemical.casNumber ?? '').isNotEmpty) ('CAS', chemical.casNumber!),
      if ((chemical.concentration ?? '').isNotEmpty)
        ('concentration', chemical.concentration!),
      if ((chemical.location ?? '').isNotEmpty)
        ('location', chemical.location!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const PageHeading('details', trailing: SizedBox.shrink()),
        NotebookCard(
          key: const Key('chemical-details-summary'),
          accent: expiryState == ExpiryState.expired
              ? context.marginRedColor
              : expiryState == ExpiryState.expiringSoon
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
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              if (chemical.expiryDate != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 108,
                        child: Text(
                          'expiry',
                          style: TextStyle(
                            color: context.mutedInkColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${formatDateOnly(chemical.expiryDate!)} · '
                          '${expiryCaption(chemical.expiryDate)}',
                          key: const Key('detail-expiry-caption'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: expiryState == ExpiryState.ok
                                ? FontWeight.w400
                                : FontWeight.w700,
                            color: expiryState == ExpiryState.ok
                                ? context.inkColor
                                : expiryColor(context, expiryState),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (chemical.hazards.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final hazard in chemical.hazards)
                      Chip(
                        key: Key('detail-hazard-${hazard.code}'),
                        avatar: Icon(
                          hazardIcon(hazard),
                          size: 16,
                          color: context.marginRedColor,
                        ),
                        label: Text('${hazard.code} ${hazard.label}'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: context.marginRedColor.withValues(alpha: .4),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
