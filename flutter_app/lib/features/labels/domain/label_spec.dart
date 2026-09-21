import '../../inventory/domain/models.dart';

/// Everything a printed or shared label needs (QR-01/02/03).
///
/// Chemical labels encode the chemical's `qr_code` exactly like the web app
/// (`labwizard:chemical:<qr_code>`), so both scanners read both kinds of
/// print-out. Apparatus labels encode the row id (`labwizard:apparatus:<id>`),
/// which never changes even when the item is renamed or re-categorised; the
/// short id printed under the name lets a person match a damaged code by eye.
class LabelSpec {
  const LabelSpec({
    required this.id,
    required this.kind,
    required this.data,
    required this.title,
    this.subtitle = '',
    this.detail = '',
  });

  factory LabelSpec.chemical(Chemical chemical) => LabelSpec(
    id: chemical.id,
    kind: ItemKind.chemical,
    data: chemicalQrData(chemical.qrCode),
    title: chemical.name,
    subtitle: chemical.formula,
  );

  factory LabelSpec.apparatus(Apparatus apparatus) {
    final serial = apparatus.serialNumber?.trim() ?? '';
    return LabelSpec(
      id: apparatus.id,
      kind: ItemKind.apparatus,
      data: apparatusQrData(apparatus.id),
      title: apparatus.name,
      subtitle: [
        apparatus.category.replaceAll('_', ' '),
        if (serial.isNotEmpty) 'S/N $serial',
      ].join(' · '),
      detail: 'ID ${shortId(apparatus.id)}',
    );
  }

  /// The item this label belongs to.
  final String id;
  final ItemKind kind;

  /// The text encoded in the QR code.
  final String data;

  /// Item name, printed bold.
  final String title;

  /// Formula for chemicals; category and serial number for apparatus.
  final String subtitle;

  /// Optional small third line (apparatus short id).
  final String detail;

  /// File-name-safe stem such as `beaker-250-ml`.
  String get fileStem {
    final stem = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return stem.isEmpty ? kind.name : stem;
  }
}

String chemicalQrData(String qrCode) => 'labwizard:chemical:$qrCode';

String apparatusQrData(String id) => 'labwizard:apparatus:$id';

/// Last eight hex characters of a uuid, upper-cased — enough to tell items
/// apart on a shelf without printing the whole id.
String shortId(String id) {
  final compact = id.replaceAll('-', '').toUpperCase();
  return compact.length <= 8
      ? compact
      : compact.substring(compact.length - 8);
}

/// Labels for the given chemicals, skipping rows that never received a QR
/// code (created before the web app generated them).
List<LabelSpec> chemicalLabels(Iterable<Chemical> chemicals) => [
  for (final chemical in chemicals)
    if (chemical.qrCode.trim().isNotEmpty) LabelSpec.chemical(chemical),
];

List<LabelSpec> apparatusLabels(Iterable<Apparatus> apparatus) => [
  for (final item in apparatus) LabelSpec.apparatus(item),
];
