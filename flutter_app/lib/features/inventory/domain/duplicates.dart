import 'models.dart';

/// Lower-cases, trims, collapses whitespace and drops punctuation so that
/// "Sodium  Chloride", "sodium-chloride" and "Sodium chloride." compare equal.
String normalizeName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-]+'), ' ')
    .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '')
    .trim();

/// Formula comparison ignores case, spaces and dot separators
/// ("CuSO4 · 5H2O" equals "cuso4.5h2o").
String normalizeFormula(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s·•.]+'), '').trim();

String normalizeCategory(String value) => normalizeName(value);

/// An existing item that looks like the one being added (DUP-01).
class DuplicateMatch {
  const DuplicateMatch({
    required this.id,
    required this.kind,
    required this.name,
    required this.detail,
    required this.reason,
  });

  final String id;
  final ItemKind kind;
  final String name;

  /// Formula/category plus quantity, for the warning card.
  final String detail;

  /// Why it matched, e.g. "same name" or "same formula".
  final String reason;
}

List<DuplicateMatch> findChemicalDuplicates({
  required Iterable<Chemical> existing,
  required String name,
  required String formula,
  String? excludeId,
}) {
  final normalizedName = normalizeName(name);
  final normalizedFormula = normalizeFormula(formula);
  if (normalizedName.isEmpty && normalizedFormula.isEmpty) return const [];
  final matches = <DuplicateMatch>[];
  for (final item in existing) {
    if (item.id == excludeId) continue;
    final sameName =
        normalizedName.isNotEmpty && normalizeName(item.name) == normalizedName;
    final sameFormula =
        normalizedFormula.isNotEmpty &&
        normalizeFormula(item.formula) == normalizedFormula;
    if (!sameName && !sameFormula) continue;
    matches.add(
      DuplicateMatch(
        id: item.id,
        kind: ItemKind.chemical,
        name: item.name,
        detail:
            '${item.formula.isEmpty ? 'no formula' : item.formula} · '
            '${formatQuantity(item.quantity)} ${item.unit}',
        reason: sameName && sameFormula
            ? 'same name and formula'
            : sameName
            ? 'same name'
            : 'same formula',
      ),
    );
  }
  return matches;
}

List<DuplicateMatch> findApparatusDuplicates({
  required Iterable<Apparatus> existing,
  required String name,
  required String category,
  String? excludeId,
}) {
  final normalizedName = normalizeName(name);
  if (normalizedName.isEmpty) return const [];
  final normalizedCategory = normalizeCategory(category);
  final matches = <DuplicateMatch>[];
  for (final item in existing) {
    if (item.id == excludeId) continue;
    if (normalizeName(item.name) != normalizedName) continue;
    final sameCategory = normalizeCategory(item.category) == normalizedCategory;
    matches.add(
      DuplicateMatch(
        id: item.id,
        kind: ItemKind.apparatus,
        name: item.name,
        detail: '${item.category} · ${formatQuantity(item.quantity)} pcs',
        reason: sameCategory
            ? 'same name and category'
            : 'same name in ${item.category}',
      ),
    );
  }
  // Exact category matches first so the most likely duplicate is on top.
  matches.sort((a, b) {
    final aExact = a.reason == 'same name and category' ? 0 : 1;
    final bExact = b.reason == 'same name and category' ? 0 : 1;
    return aExact.compareTo(bExact);
  });
  return matches;
}
