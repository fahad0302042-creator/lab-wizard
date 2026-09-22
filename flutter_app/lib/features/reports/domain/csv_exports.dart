/// Spreadsheet exports of the report page (REPORT-05). Every cell goes
/// through `csvCell`, so notes or names such as `=HYPERLINK(...)` can never
/// become formulas when the file is opened.
library;

import 'package:intl/intl.dart';

import '../../../core/utils/csv.dart';
import '../../inventory/domain/models.dart';
import 'report_range.dart';

/// Activity of [kind] inside [range], oldest first.
String activityCsv({
  required ReportRange range,
  required ItemKind kind,
  required Iterable<ConsumptionLog> logs,
  required String Function(String itemId) nameOf,
  required String Function(String itemId) detailOf,
  required String Function(String itemId) unitOf,
}) {
  final day = DateFormat('yyyy-MM-dd');
  final clock = DateFormat('HH:mm');
  final selected =
      logs
          .where((log) => log.itemType == kind && range.contains(log.loggedAt))
          .toList()
        ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  return csvDocument(
    [
      'date',
      'time',
      'item',
      kind == ItemKind.chemical ? 'formula' : 'category',
      'action',
      'amount',
      'unit',
      'note',
      'entry id',
      'logged at (UTC)',
    ],
    selected.map((log) {
      final local = log.loggedAt.toLocal();
      return [
        day.format(local),
        clock.format(local),
        nameOf(log.itemId),
        detailOf(log.itemId),
        log.action.name,
        log.amount,
        kind == ItemKind.apparatus ? 'pcs' : unitOf(log.itemId),
        log.note,
        log.id,
        log.loggedAt.toUtc().toIso8601String(),
      ];
    }),
  );
}

/// The chemical shelf with every DATA-01 column, sorted by name.
String chemicalsCsv(Iterable<Chemical> chemicals) {
  final items = chemicals.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return csvDocument(
    const [
      'name',
      'formula',
      'quantity',
      'unit',
      'initial quantity',
      'low stock level',
      'stock',
      'supplier',
      'cas number',
      'concentration',
      'location',
      'expiry date',
      'hazards',
      'barcode',
      'qr code',
      'notes',
      'added',
    ],
    items.map(
      (item) => [
        item.name,
        item.formula,
        item.quantity,
        item.unit,
        item.initialQuantity,
        item.lowStockThreshold,
        item.stockState.name,
        item.supplier,
        item.casNumber,
        item.concentration,
        item.location,
        item.expiryDate == null ? null : formatDateOnly(item.expiryDate!),
        item.hazardClasses.join(';'),
        item.barcode,
        item.qrCode,
        item.notes,
        formatDateOnly(item.createdAt.toLocal()),
      ],
    ),
  );
}

/// The apparatus shelf with every GEAR-01 column, sorted by name.
String apparatusCsv(Iterable<Apparatus> apparatus) {
  final items = apparatus.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return csvDocument(
    const [
      'name',
      'category',
      'quantity',
      'unit',
      'initial quantity',
      'low stock level',
      'stock',
      'serial number',
      'condition',
      'assigned to',
      'location',
      'purchase date',
      'warranty until',
      'barcode',
      'notes',
      'added',
    ],
    items.map(
      (item) => [
        item.name,
        item.category,
        item.quantity,
        'pcs',
        item.initialQuantity,
        item.lowStockThreshold,
        item.stockState.name,
        item.serialNumber,
        item.condition,
        item.assignedTo,
        item.location,
        item.purchaseDate == null ? null : formatDateOnly(item.purchaseDate!),
        item.warrantyUntil == null ? null : formatDateOnly(item.warrantyUntil!),
        item.barcode,
        item.notes,
        formatDateOnly(item.createdAt.toLocal()),
      ],
    ),
  );
}
