import '../../inventory/domain/models.dart';

/// A scanned code that matched an item in the local inventory.
class ScanMatch {
  const ScanMatch({
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
    this.viaBarcode = false,
  });

  /// Builds the match for an inventory item.
  factory ScanMatch.chemical(Chemical item, {bool viaBarcode = false}) =>
      ScanMatch(
        kind: ItemKind.chemical,
        id: item.id,
        name: item.name,
        subtitle: item.formula,
        viaBarcode: viaBarcode,
      );

  factory ScanMatch.apparatus(Apparatus item, {bool viaBarcode = false}) =>
      ScanMatch(
        kind: ItemKind.apparatus,
        id: item.id,
        name: item.name,
        subtitle: item.category.replaceAll('_', ' '),
        viaBarcode: viaBarcode,
      );

  final ItemKind kind;
  final String id;
  final String name;
  final String subtitle;

  /// True when the code was an explicitly linked external barcode (SCAN-04)
  /// rather than a Lab Wizard label.
  final bool viaBarcode;
}

/// The two payload prefixes shared with the web app's label printer.
const chemicalCodePrefix = 'labwizard:chemical:';
const apparatusCodePrefix = 'labwizard:apparatus:';

/// Maps the raw text of a scanned code onto an inventory item.
///
/// * `labwizard:chemical:<qr_code>` and bare codes (labels printed before the
///   prefix existed) match a chemical by its `qr_code`.
/// * `labwizard:apparatus:<id>` matches an apparatus row by id; an apparatus
///   payload never falls back to the chemical lookup.
/// * Any other text matches only an item whose linked `barcode` equals it
///   exactly (SCAN-04). Product codes are never guessed from.
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
      if (item.id == id) return ScanMatch.apparatus(item);
    }
    return null;
  }
  final code = text.startsWith(chemicalCodePrefix)
      ? text.substring(chemicalCodePrefix.length).trim()
      : text;
  if (code.isEmpty) return null;
  for (final item in chemicals) {
    if (item.qrCode == code) return ScanMatch.chemical(item);
  }
  if (text.startsWith(chemicalCodePrefix)) return null;
  return findLinkedBarcode(text, chemicals: chemicals, apparatus: apparatus);
}

/// The item a person explicitly linked to [code], if any (SCAN-04).
ScanMatch? findLinkedBarcode(
  String code, {
  required Iterable<Chemical> chemicals,
  required Iterable<Apparatus> apparatus,
}) {
  final text = code.trim();
  if (text.isEmpty) return null;
  for (final item in chemicals) {
    if (item.barcode == text) return ScanMatch.chemical(item, viaBarcode: true);
  }
  for (final item in apparatus) {
    if (item.barcode == text) {
      return ScanMatch.apparatus(item, viaBarcode: true);
    }
  }
  return null;
}

/// True for payloads printed by Lab Wizard itself.
bool isLabWizardCode(String raw) {
  final text = raw.trim();
  return text.startsWith(chemicalCodePrefix) ||
      text.startsWith(apparatusCodePrefix);
}
