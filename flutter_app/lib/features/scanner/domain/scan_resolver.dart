import '../../inventory/domain/models.dart';

/// A scanned code that matched an item in the local inventory.
class ScanMatch {
  const ScanMatch({
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final ItemKind kind;
  final String id;
  final String name;
  final String subtitle;
}

/// The two payload prefixes shared with the web app's label printer.
const chemicalCodePrefix = 'labwizard:chemical:';
const apparatusCodePrefix = 'labwizard:apparatus:';

/// Maps the raw text of a QR code onto an inventory item.
///
/// * `labwizard:chemical:<qr_code>` and bare codes (labels printed before the
///   prefix existed) match a chemical by its `qr_code`.
/// * `labwizard:apparatus:<id>` matches an apparatus row by id; an apparatus
///   payload never falls back to the chemical lookup.
///
/// Returns null when nothing in the notebook carries that code.
ScanMatch? resolveScan(
  String raw, {
  required Iterable<Chemical> chemicals,
  required Iterable<Apparatus> apparatus,
}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.startsWith(apparatusCodePrefix)) {
    final id = text.substring(apparatusCodePrefix.length).trim();
    for (final item in apparatus) {
      if (item.id == id) {
        return ScanMatch(
          kind: ItemKind.apparatus,
          id: item.id,
          name: item.name,
          subtitle: item.category.replaceAll('_', ' '),
        );
      }
    }
    return null;
  }
  final code = text.startsWith(chemicalCodePrefix)
      ? text.substring(chemicalCodePrefix.length).trim()
      : text;
  if (code.isEmpty) return null;
  for (final item in chemicals) {
    if (item.qrCode == code) {
      return ScanMatch(
        kind: ItemKind.chemical,
        id: item.id,
        name: item.name,
        subtitle: item.formula,
      );
    }
  }
  return null;
}
