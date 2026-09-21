import '../../../core/utils/csv.dart';
import '../../inventory/domain/duplicates.dart';
import '../../inventory/domain/models.dart';

/// Columns the CSV import understands (IMPORT-01). `type` lets one file
/// carry both shelves, matching the app's own CSV export.
enum ImportField {
  type('type', ['type', 'kind', 'shelf']),
  name('name', ['name', 'item', 'chemical', 'reagent', 'apparatus', 'title']),
  formula('formula', ['formula', 'formula/category', 'chemical formula']),
  category('category', ['category', 'formula/category', 'group']),
  quantity('quantity', ['quantity', 'qty', 'amount', 'stock', 'count']),
  unit('unit', ['unit', 'units', 'uom']),
  threshold('low-stock level', [
    'low stock level',
    'low_stock_threshold',
    'threshold',
    'low stock',
    'minimum',
    'min',
    'reorder level',
  ]),
  notes('notes', ['notes', 'note', 'comment', 'comments', 'remarks']),
  supplier('supplier', ['supplier', 'vendor', 'manufacturer', 'brand']),
  casNumber('CAS number', ['cas number', 'cas', 'cas_number', 'cas no']),
  concentration('concentration', ['concentration', 'purity', 'grade']),
  location('location', ['location', 'storage', 'cabinet', 'shelf location']),
  expiryDate('expiry date', [
    'expiry date',
    'expiry',
    'expires',
    'expiration',
    'expiration date',
    'expiry_date',
    'best before',
  ]),
  hazards('hazards', [
    'hazards',
    'hazard',
    'ghs',
    'hazard classes',
    'pictograms',
  ]),
  serialNumber('serial number', [
    'serial number',
    'serial',
    'serial no',
    'asset tag',
    'asset',
  ]),
  condition('condition', ['condition', 'state']),
  assignedTo('assigned to', ['assigned to', 'assigned', 'assignee', 'owner']),
  purchaseDate('purchase date', [
    'purchase date',
    'purchased',
    'bought',
    'acquired',
  ]),
  warrantyUntil('warranty until', [
    'warranty until',
    'warranty',
    'warranty end',
    'warranty expiry',
  ]);

  const ImportField(this.label, this.aliases);

  final String label;
  final List<String> aliases;

  bool get chemicalOnly => switch (this) {
    ImportField.formula ||
    ImportField.unit ||
    ImportField.supplier ||
    ImportField.casNumber ||
    ImportField.concentration ||
    ImportField.expiryDate ||
    ImportField.hazards => true,
    _ => false,
  };

  bool get apparatusOnly => switch (this) {
    ImportField.category ||
    ImportField.serialNumber ||
    ImportField.condition ||
    ImportField.assignedTo ||
    ImportField.purchaseDate ||
    ImportField.warrantyUntil => true,
    _ => false,
  };
}

/// Which shelf rows go to. [auto] reads it from a `type` column.
enum ImportTarget { chemicals, apparatus, auto }

String normalizeHeader(String header) => header
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[_\-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Guesses a column for every field from the header row. Later exact alias
/// matches never steal a column from an earlier field, and a column is used
/// at most once — except `formula/category`, which serves both fields
/// because the app's own export shares that column.
Map<ImportField, int> autoMapHeaders(List<String> headers) {
  final normalized = headers.map(normalizeHeader).toList();
  final mapping = <ImportField, int>{};
  final taken = <int>{};
  for (final field in ImportField.values) {
    var chosen = -1;
    for (final alias in field.aliases) {
      final index = normalized.indexOf(alias);
      if (index >= 0 && (!taken.contains(index) || alias.contains('/'))) {
        chosen = index;
        break;
      }
    }
    if (chosen < 0) {
      for (var index = 0; index < normalized.length; index++) {
        if (taken.contains(index)) continue;
        final primary = field.aliases.first;
        if (primary.length > 3 && normalized[index].contains(primary)) {
          chosen = index;
          break;
        }
      }
    }
    if (chosen >= 0) {
      mapping[field] = chosen;
      taken.add(chosen);
    }
  }
  return mapping;
}

/// Whether the first row looks like a header instead of data.
bool looksLikeHeader(List<String> firstRow) {
  final normalized = firstRow.map(normalizeHeader).toSet();
  final known = ImportField.values
      .expand((field) => field.aliases)
      .where(normalized.contains)
      .length;
  return known >= 2;
}

enum ImportIssueLevel { error, warning }

class ImportIssue {
  const ImportIssue(this.level, this.message);

  final ImportIssueLevel level;
  final String message;

  bool get isError => level == ImportIssueLevel.error;

  @override
  String toString() => message;
}

/// One CSV row after mapping and validation.
class ImportRow {
  ImportRow({
    required this.line,
    required this.kind,
    required this.name,
    required this.subtitle,
    required this.quantity,
    required this.unit,
    required this.threshold,
    required this.notes,
    required this.details,
    required this.gear,
    required this.issues,
    required this.duplicates,
  });

  /// 1-based line number in the file (header counted).
  final int line;
  final ItemKind? kind;
  final String name;

  /// Formula for chemicals, category for apparatus.
  final String subtitle;
  final double quantity;
  final String unit;
  final double threshold;
  final String notes;
  final ChemicalDetails details;
  final ApparatusDetails gear;
  final List<ImportIssue> issues;

  /// Existing shelf items this row appears to duplicate.
  final List<DuplicateMatch> duplicates;

  bool get hasErrors => issues.any((issue) => issue.isError);
  bool get isDuplicate => duplicates.isNotEmpty;
  bool get hasWarnings => issues.any((issue) => !issue.isError);

  String get summary => [
    if (name.isNotEmpty) name else 'line $line',
    if (subtitle.isNotEmpty) subtitle,
    '${formatImportNumber(quantity)} $unit',
  ].join(' · ');
}

const knownUnits = ['mL', 'g', 'mg', 'L', 'kg', 'drops', 'pcs'];
const knownCategories = [
  'glassware',
  'balances',
  'heating',
  'measurement',
  'other',
];

String formatImportNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// Maps and validates every data row of a parsed CSV.
List<ImportRow> buildImportRows({
  required List<List<String>> rows,
  required Map<ImportField, int> mapping,
  required ImportTarget target,
  required bool hasHeader,
  required List<Chemical> existingChemicals,
  required List<Apparatus> existingApparatus,
}) {
  final result = <ImportRow>[];
  final seenChemicals = <String>{};
  final seenApparatus = <String>{};
  final start = hasHeader ? 1 : 0;
  for (var index = start; index < rows.length; index++) {
    final cells = rows[index];
    String cell(ImportField field) {
      final column = mapping[field];
      if (column == null || column < 0 || column >= cells.length) return '';
      // Our own exports guard formula-looking text with an apostrophe
      // (REPORT-05); take it off again on the way back in.
      return csvUnguard(cells[column].trim());
    }

    final issues = <ImportIssue>[];
    ItemKind? kind;
    switch (target) {
      case ImportTarget.chemicals:
        kind = ItemKind.chemical;
      case ImportTarget.apparatus:
        kind = ItemKind.apparatus;
      case ImportTarget.auto:
        final typeText = cell(ImportField.type).toLowerCase();
        if (typeText.startsWith('chem') || typeText.startsWith('reagent')) {
          kind = ItemKind.chemical;
        } else if (typeText.startsWith('app') ||
            typeText.startsWith('equip') ||
            typeText.startsWith('gear')) {
          kind = ItemKind.apparatus;
        } else {
          issues.add(
            ImportIssue(
              ImportIssueLevel.error,
              typeText.isEmpty
                  ? 'Missing type (chemical or apparatus)'
                  : 'Unknown type "$typeText"',
            ),
          );
        }
    }

    final name = cell(ImportField.name);
    if (name.isEmpty) {
      issues.add(const ImportIssue(ImportIssueLevel.error, 'Missing name'));
    } else if (name.length > 120) {
      issues.add(
        const ImportIssue(ImportIssueLevel.error, 'Name is longer than 120'),
      );
    }

    final quantityText = cell(ImportField.quantity);
    var quantity = 0.0;
    if (quantityText.isEmpty) {
      issues.add(
        const ImportIssue(ImportIssueLevel.warning, 'No quantity, using 0'),
      );
    } else {
      final parsed = double.tryParse(quantityText.replaceAll(',', '.'));
      if (parsed == null || parsed.isNaN || parsed.isInfinite) {
        issues.add(
          ImportIssue(
            ImportIssueLevel.error,
            'Quantity "$quantityText" is not a number',
          ),
        );
      } else if (parsed < 0) {
        issues.add(
          const ImportIssue(ImportIssueLevel.error, 'Quantity is negative'),
        );
      } else {
        quantity = parsed;
      }
    }

    final thresholdText = cell(ImportField.threshold);
    var threshold = 0.0;
    if (thresholdText.isNotEmpty) {
      final parsed = double.tryParse(thresholdText.replaceAll(',', '.'));
      if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
        issues.add(
          ImportIssue(
            ImportIssueLevel.error,
            'Low-stock level "$thresholdText" is not a number of 0 or more',
          ),
        );
      } else {
        threshold = parsed;
      }
    }

    var unit = 'pcs';
    var subtitle = '';
    var details = const ChemicalDetails();
    var gear = const ApparatusDetails();
    if (kind == ItemKind.chemical) {
      subtitle = cell(ImportField.formula);
      final unitText = cell(ImportField.unit);
      final matched = knownUnits.where(
        (known) => known.toLowerCase() == unitText.toLowerCase(),
      );
      if (unitText.isEmpty) {
        unit = 'mL';
        issues.add(
          const ImportIssue(ImportIssueLevel.warning, 'No unit, using mL'),
        );
      } else if (matched.isEmpty) {
        unit = 'mL';
        issues.add(
          ImportIssue(
            ImportIssueLevel.warning,
            'Unknown unit "$unitText", using mL',
          ),
        );
      } else {
        unit = matched.first;
      }
      final cas = cell(ImportField.casNumber);
      if (cas.isNotEmpty && !isValidCasNumber(cas)) {
        issues.add(
          ImportIssue(ImportIssueLevel.error, 'CAS number "$cas" is invalid'),
        );
      }
      final expiryText = cell(ImportField.expiryDate);
      DateTime? expiry;
      if (expiryText.isNotEmpty) {
        expiry = parseImportDate(expiryText);
        if (expiry == null) {
          issues.add(
            ImportIssue(
              ImportIssueLevel.error,
              'Expiry "$expiryText" is not a date (use YYYY-MM-DD)',
            ),
          );
        }
      }
      final hazardText = cell(ImportField.hazards);
      final hazards = parseHazardList(hazardText);
      if (hazardText.isNotEmpty && hazards.isEmpty) {
        issues.add(
          ImportIssue(
            ImportIssueLevel.warning,
            'Hazards "$hazardText" not recognised (use GHS01–GHS09)',
          ),
        );
      }
      details = ChemicalDetails(
        supplier: cell(ImportField.supplier),
        casNumber: cas,
        concentration: cell(ImportField.concentration),
        location: cell(ImportField.location),
        expiryDate: expiry,
        hazardClasses: hazards,
      );
      if (quantity != quantity.roundToDouble() && unit == 'pcs') {
        issues.add(
          const ImportIssue(
            ImportIssueLevel.warning,
            'Fractional quantity for a piece count',
          ),
        );
      }
    } else if (kind == ItemKind.apparatus) {
      final categoryText = cell(ImportField.category).toLowerCase();
      if (categoryText.isEmpty) {
        subtitle = 'other';
        issues.add(
          const ImportIssue(
            ImportIssueLevel.warning,
            'No category, using "other"',
          ),
        );
      } else if (knownCategories.contains(categoryText)) {
        subtitle = categoryText;
      } else {
        subtitle = 'other';
        issues.add(
          ImportIssue(
            ImportIssueLevel.warning,
            'Unknown category "$categoryText", using "other"',
          ),
        );
      }
      if (quantity != quantity.roundToDouble()) {
        issues.add(
          const ImportIssue(
            ImportIssueLevel.error,
            'Apparatus counts must be whole numbers',
          ),
        );
      }
      final conditionText = cell(ImportField.condition);
      final condition = ApparatusCondition.fromLabel(conditionText);
      if (conditionText.isNotEmpty && condition == null) {
        issues.add(
          ImportIssue(
            ImportIssueLevel.warning,
            'Condition "$conditionText" kept as written (not one of '
            'good / fair / needs repair / retired)',
          ),
        );
      }
      DateTime? purchase;
      final purchaseText = cell(ImportField.purchaseDate);
      if (purchaseText.isNotEmpty) {
        purchase = parseImportDate(purchaseText);
        if (purchase == null) {
          issues.add(
            ImportIssue(
              ImportIssueLevel.error,
              'Purchase date "$purchaseText" is not a date (use YYYY-MM-DD)',
            ),
          );
        }
      }
      DateTime? warranty;
      final warrantyText = cell(ImportField.warrantyUntil);
      if (warrantyText.isNotEmpty) {
        warranty = parseImportDate(warrantyText);
        if (warranty == null) {
          issues.add(
            ImportIssue(
              ImportIssueLevel.error,
              'Warranty date "$warrantyText" is not a date (use YYYY-MM-DD)',
            ),
          );
        }
      }
      gear = ApparatusDetails(
        serialNumber: cell(ImportField.serialNumber),
        condition: condition?.label ?? conditionText,
        assignedTo: cell(ImportField.assignedTo),
        location: cell(ImportField.location),
        purchaseDate: purchase,
        warrantyUntil: warranty,
      );
    }

    final duplicates = <DuplicateMatch>[];
    if (name.isNotEmpty && kind != null) {
      if (kind == ItemKind.chemical) {
        duplicates.addAll(
          findChemicalDuplicates(
            existing: existingChemicals,
            name: name,
            formula: subtitle,
          ),
        );
        final key = '${normalizeName(name)}|${normalizeFormula(subtitle)}';
        if (!seenChemicals.add(key)) {
          issues.add(
            const ImportIssue(
              ImportIssueLevel.warning,
              'Repeated earlier in this file',
            ),
          );
        }
      } else {
        duplicates.addAll(
          findApparatusDuplicates(
            existing: existingApparatus,
            name: name,
            category: subtitle,
          ),
        );
        final key = '${normalizeName(name)}|${normalizeCategory(subtitle)}';
        if (!seenApparatus.add(key)) {
          issues.add(
            const ImportIssue(
              ImportIssueLevel.warning,
              'Repeated earlier in this file',
            ),
          );
        }
      }
    }

    result.add(
      ImportRow(
        line: index + 1,
        kind: kind,
        name: name,
        subtitle: subtitle,
        quantity: quantity,
        unit: unit,
        threshold: threshold,
        notes: cell(ImportField.notes),
        details: details,
        gear: gear,
        issues: issues,
        duplicates: duplicates,
      ),
    );
  }
  return result;
}

/// Accepts ISO dates, `DD/MM/YYYY`, `DD.MM.YYYY` and `MM/DD/YYYY` (only when
/// the first number cannot be a day).
DateTime? parseImportDate(String text) {
  final trimmed = text.trim();
  final iso = parseDateOnly(trimmed);
  if (iso != null && RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(trimmed)) {
    return iso;
  }
  final match = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$')
      .firstMatch(trimmed);
  if (match == null) return null;
  var first = int.parse(match.group(1)!);
  var second = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  // Day-first by default; month-first only when the first number cannot be
  // a month.
  if (second > 12 && first <= 12) {
    final swap = first;
    first = second;
    second = swap;
  }
  if (first < 1 || first > 31 || second < 1 || second > 12) return null;
  final date = DateTime(year, second, first);
  if (date.month != second || date.day != first) return null;
  return date;
}

/// Counts used by the preview header and the final report.
class ImportSummary {
  const ImportSummary({
    required this.total,
    required this.ready,
    required this.withWarnings,
    required this.duplicates,
    required this.errors,
  });

  factory ImportSummary.of(List<ImportRow> rows) {
    var ready = 0;
    var warnings = 0;
    var duplicates = 0;
    var errors = 0;
    for (final row in rows) {
      if (row.hasErrors) {
        errors++;
      } else if (row.isDuplicate) {
        duplicates++;
      } else {
        ready++;
        if (row.hasWarnings) warnings++;
      }
    }
    return ImportSummary(
      total: rows.length,
      ready: ready,
      withWarnings: warnings,
      duplicates: duplicates,
      errors: errors,
    );
  }

  final int total;
  final int ready;
  final int withWarnings;
  final int duplicates;
  final int errors;
}

/// Plain-text report of rows that were skipped or failed, shareable after a
/// partial import.
String buildImportReport({
  required String fileName,
  required int imported,
  required List<(ImportRow, String)> problems,
}) {
  final buffer = StringBuffer()
    ..writeln('Lab Wizard import report — $fileName')
    ..writeln('Imported: $imported')
    ..writeln('Not imported: ${problems.length}')
    ..writeln();
  for (final (row, reason) in problems) {
    buffer.writeln('line ${row.line}: ${row.summary} — $reason');
  }
  return buffer.toString();
}
