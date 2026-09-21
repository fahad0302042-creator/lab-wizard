import 'dart:convert';

import 'package:intl/intl.dart';

enum ItemKind { chemical, apparatus }

enum InventoryAction { consume, restock, breakage }

enum StockState { healthy, low, empty }

double _asDouble(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

String formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Optional chemical metadata columns added by
/// `supabase/003_chemical_metadata.sql` (DATA-01). Everything is nullable so
/// rows created by the web app or before the migration stay valid.
const chemicalMetadataColumns = {
  'supplier',
  'cas_number',
  'concentration',
  'location',
  'expiry_date',
  'hazard_classes',
};

/// Days before the expiry date at which a chemical counts as "expiring".
const expiryWarningWindow = Duration(days: 30);

enum ExpiryState { none, ok, expiringSoon, expired }

/// GHS hazard pictograms, used as chips on forms and in the item detail.
enum HazardClass {
  explosive('GHS01', 'explosive'),
  flammable('GHS02', 'flammable'),
  oxidizing('GHS03', 'oxidizing'),
  compressedGas('GHS04', 'gas under pressure'),
  corrosive('GHS05', 'corrosive'),
  toxic('GHS06', 'acutely toxic'),
  irritant('GHS07', 'harmful / irritant'),
  healthHazard('GHS08', 'health hazard'),
  environmental('GHS09', 'environmental hazard');

  const HazardClass(this.code, this.label);

  final String code;
  final String label;

  static HazardClass? fromCode(String value) {
    final normalized = value.trim().toUpperCase();
    for (final hazard in values) {
      if (hazard.code == normalized ||
          hazard.name.toUpperCase() == normalized) {
        return hazard;
      }
    }
    return null;
  }
}

class Chemical {
  const Chemical({
    required this.id,
    required this.name,
    required this.formula,
    required this.unit,
    required this.quantity,
    required this.initialQuantity,
    required this.lowStockThreshold,
    required this.notes,
    required this.qrCode,
    required this.createdAt,
    this.supplier,
    this.casNumber,
    this.concentration,
    this.location,
    this.expiryDate,
    this.hazardClasses = const [],
  });

  final String id;
  final String name;
  final String formula;
  final String unit;
  final double quantity;
  final double initialQuantity;
  final double lowStockThreshold;
  final String notes;
  final String qrCode;
  final DateTime createdAt;
  final String? supplier;
  final String? casNumber;
  final String? concentration;
  final String? location;

  /// Calendar date (local); the time component is ignored.
  final DateTime? expiryDate;
  final List<String> hazardClasses;

  bool get hasMetadata =>
      (supplier ?? '').isNotEmpty ||
      (casNumber ?? '').isNotEmpty ||
      (concentration ?? '').isNotEmpty ||
      (location ?? '').isNotEmpty ||
      expiryDate != null ||
      hazardClasses.isNotEmpty;

  List<HazardClass> get hazards => [
    for (final code in hazardClasses) ?HazardClass.fromCode(code),
  ];

  ExpiryState expiryState({DateTime? now}) =>
      expiryStateFor(expiryDate, now: now);

  StockState get stockState {
    if (quantity <= 0) return StockState.empty;
    if (lowStockThreshold > 0 && quantity <= lowStockThreshold) {
      return StockState.low;
    }
    return StockState.healthy;
  }

  double get stockProgress {
    if (quantity <= 0) return 0;
    final target = lowStockThreshold > 0
        ? lowStockThreshold * 2
        : initialQuantity;
    if (target <= 0) return 1;
    return (quantity / target).clamp(0, 1);
  }

  Chemical copyWith({
    String? name,
    String? formula,
    String? unit,
    double? quantity,
    double? initialQuantity,
    double? lowStockThreshold,
    String? notes,
    String? qrCode,
    String? supplier,
    String? casNumber,
    String? concentration,
    String? location,
    DateTime? expiryDate,
    List<String>? hazardClasses,
  }) => Chemical(
    id: id,
    name: name ?? this.name,
    formula: formula ?? this.formula,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    initialQuantity: initialQuantity ?? this.initialQuantity,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    notes: notes ?? this.notes,
    qrCode: qrCode ?? this.qrCode,
    createdAt: createdAt,
    supplier: supplier ?? this.supplier,
    casNumber: casNumber ?? this.casNumber,
    concentration: concentration ?? this.concentration,
    location: location ?? this.location,
    expiryDate: expiryDate ?? this.expiryDate,
    hazardClasses: hazardClasses ?? this.hazardClasses,
  );

  factory Chemical.fromMap(Map<String, dynamic> map) => Chemical(
    id: map['id'] as String,
    name: (map['name'] as String?) ?? '',
    formula: (map['formula'] as String?) ?? '',
    unit: (map['unit'] as String?) ?? 'mL',
    quantity: _asDouble(map['quantity']),
    initialQuantity: _asDouble(map['initial_quantity']),
    lowStockThreshold: _asDouble(map['low_stock_threshold']),
    notes: (map['notes'] as String?) ?? '',
    qrCode: (map['qr_code'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((map['created_at'] as String?) ?? '') ??
        DateTime.now(),
    supplier: _emptyToNull(map['supplier']),
    casNumber: _emptyToNull(map['cas_number']),
    concentration: _emptyToNull(map['concentration']),
    location: _emptyToNull(map['location']),
    expiryDate: parseDateOnly(map['expiry_date']),
    hazardClasses: parseHazardList(map['hazard_classes']),
  );

  /// Row shape shared with the server. Metadata keys are only present when
  /// set, so devices talking to a pre-migration schema keep working.
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'formula': formula,
    'unit': unit,
    'quantity': quantity,
    'initial_quantity': initialQuantity,
    'low_stock_threshold': lowStockThreshold,
    'notes': notes,
    'qr_code': qrCode,
    'created_at': createdAt.toIso8601String(),
    ...metadataMap(),
  };

  /// Only the DATA-01 columns, null-free, for inserts and updates.
  Map<String, dynamic> metadataMap() => {
    if ((supplier ?? '').isNotEmpty) 'supplier': supplier,
    if ((casNumber ?? '').isNotEmpty) 'cas_number': casNumber,
    if ((concentration ?? '').isNotEmpty) 'concentration': concentration,
    if ((location ?? '').isNotEmpty) 'location': location,
    if (expiryDate != null) 'expiry_date': formatDateOnly(expiryDate!),
    if (hazardClasses.isNotEmpty) 'hazard_classes': hazardClasses,
  };
}

/// Optional DATA-01 metadata captured by the chemical forms and CSV import.
class ChemicalDetails {
  const ChemicalDetails({
    this.supplier,
    this.casNumber,
    this.concentration,
    this.location,
    this.expiryDate,
    this.hazardClasses = const [],
  });

  factory ChemicalDetails.of(Chemical chemical) => ChemicalDetails(
    supplier: chemical.supplier,
    casNumber: chemical.casNumber,
    concentration: chemical.concentration,
    location: chemical.location,
    expiryDate: chemical.expiryDate,
    hazardClasses: chemical.hazardClasses,
  );

  final String? supplier;
  final String? casNumber;
  final String? concentration;
  final String? location;
  final DateTime? expiryDate;
  final List<String> hazardClasses;

  bool get isEmpty =>
      _emptyToNull(supplier) == null &&
      _emptyToNull(casNumber) == null &&
      _emptyToNull(concentration) == null &&
      _emptyToNull(location) == null &&
      expiryDate == null &&
      hazardClasses.isEmpty;

  /// Full column map for updates; nulls clear a column on the server.
  Map<String, dynamic> toChanges() => {
    'supplier': _emptyToNull(supplier),
    'cas_number': _emptyToNull(casNumber),
    'concentration': _emptyToNull(concentration),
    'location': _emptyToNull(location),
    'expiry_date': expiryDate == null ? null : formatDateOnly(expiryDate!),
    'hazard_classes': parseHazardList(hazardClasses),
  };

  bool sameAs(ChemicalDetails other) {
    final mine = toChanges();
    final theirs = other.toChanges();
    for (final key in mine.keys) {
      if (key == 'hazard_classes') {
        final a = mine[key] as List<String>;
        final b = theirs[key] as List<String>;
        if (a.length != b.length) return false;
        for (var index = 0; index < a.length; index++) {
          if (a[index] != b[index]) return false;
        }
      } else if (mine[key] != theirs[key]) {
        return false;
      }
    }
    return true;
  }
}

String? _emptyToNull(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// Parses `YYYY-MM-DD` (or a full timestamp) into a local calendar date.
/// Out-of-range parts such as month 13 are rejected instead of rolling over.
DateTime? parseDateOnly(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

String formatDateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Accepts a JSON array, a Postgres array literal (`{GHS02,GHS07}`) or a
/// separated string ("GHS02; GHS07") and returns clean upper-case codes.
List<String> parseHazardList(Object? value) {
  if (value == null) return const [];
  final Iterable<String> parts;
  if (value is Iterable) {
    parts = value.map((entry) => entry.toString());
  } else {
    parts = value
        .toString()
        .replaceAll(RegExp(r'[{}"\[\]]'), '')
        .split(RegExp(r'[;,|/]+'));
  }
  final codes = <String>[];
  for (final part in parts) {
    final code = HazardClass.fromCode(part)?.code;
    if (code != null && !codes.contains(code)) codes.add(code);
  }
  return codes;
}

ExpiryState expiryStateFor(DateTime? expiryDate, {DateTime? now}) {
  if (expiryDate == null) return ExpiryState.none;
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
  if (expiry.isBefore(today)) return ExpiryState.expired;
  if (!expiry.isAfter(today.add(expiryWarningWindow))) {
    return ExpiryState.expiringSoon;
  }
  return ExpiryState.ok;
}

/// Checks the CAS Registry Number format and its check digit.
bool isValidCasNumber(String value) {
  final match = RegExp(r'^(\d{2,7})-(\d{2})-(\d)$').firstMatch(value.trim());
  if (match == null) return false;
  final digits = '${match.group(1)}${match.group(2)}';
  var sum = 0;
  for (var index = 0; index < digits.length; index++) {
    final digit = int.parse(digits[digits.length - 1 - index]);
    sum += digit * (index + 1);
  }
  return sum % 10 == int.parse(match.group(3)!);
}

/// Optional apparatus metadata columns added by
/// `supabase/004_apparatus_metadata.sql` (GEAR-01). All nullable.
const apparatusMetadataColumns = {
  'serial_number',
  'condition',
  'assigned_to',
  'location',
  'purchase_date',
  'warranty_until',
};

/// Condition values offered by the forms; stored as plain text.
enum ApparatusCondition {
  good('good'),
  fair('fair'),
  needsRepair('needs repair'),
  retired('retired');

  const ApparatusCondition(this.label);

  final String label;

  static ApparatusCondition? fromLabel(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final condition in values) {
      if (condition.label == normalized || condition.name == normalized) {
        return condition;
      }
    }
    return null;
  }
}

class Apparatus {
  const Apparatus({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.initialQuantity,
    required this.lowStockThreshold,
    required this.notes,
    required this.createdAt,
    this.serialNumber,
    this.condition,
    this.assignedTo,
    this.location,
    this.purchaseDate,
    this.warrantyUntil,
  });

  final String id;
  final String name;
  final String category;
  final double quantity;
  final double initialQuantity;
  final double lowStockThreshold;
  final String notes;
  final DateTime createdAt;
  final String? serialNumber;

  /// Free text; the forms offer [ApparatusCondition] values.
  final String? condition;
  final String? assignedTo;
  final String? location;
  final DateTime? purchaseDate;
  final DateTime? warrantyUntil;

  bool get hasMetadata =>
      (serialNumber ?? '').isNotEmpty ||
      (condition ?? '').isNotEmpty ||
      (assignedTo ?? '').isNotEmpty ||
      (location ?? '').isNotEmpty ||
      purchaseDate != null ||
      warrantyUntil != null;

  ApparatusCondition? get conditionValue =>
      ApparatusCondition.fromLabel(condition);

  /// Warranty expiry uses the same 30 day warning window as chemicals.
  ExpiryState warrantyState({DateTime? now}) =>
      expiryStateFor(warrantyUntil, now: now);

  StockState get stockState {
    if (quantity <= 0) return StockState.empty;
    if (lowStockThreshold > 0 && quantity <= lowStockThreshold) {
      return StockState.low;
    }
    return StockState.healthy;
  }

  double get stockProgress {
    if (quantity <= 0) return 0;
    final target = lowStockThreshold > 0
        ? lowStockThreshold * 2
        : initialQuantity;
    if (target <= 0) return 1;
    return (quantity / target).clamp(0, 1);
  }

  Apparatus copyWith({
    String? name,
    String? category,
    double? quantity,
    double? initialQuantity,
    double? lowStockThreshold,
    String? notes,
    String? serialNumber,
    String? condition,
    String? assignedTo,
    String? location,
    DateTime? purchaseDate,
    DateTime? warrantyUntil,
  }) => Apparatus(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    quantity: quantity ?? this.quantity,
    initialQuantity: initialQuantity ?? this.initialQuantity,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    serialNumber: serialNumber ?? this.serialNumber,
    condition: condition ?? this.condition,
    assignedTo: assignedTo ?? this.assignedTo,
    location: location ?? this.location,
    purchaseDate: purchaseDate ?? this.purchaseDate,
    warrantyUntil: warrantyUntil ?? this.warrantyUntil,
  );

  factory Apparatus.fromMap(Map<String, dynamic> map) => Apparatus(
    id: map['id'] as String,
    name: (map['name'] as String?) ?? '',
    category: (map['category'] as String?) ?? 'other',
    quantity: _asDouble(map['quantity']),
    initialQuantity: _asDouble(map['initial_quantity']),
    lowStockThreshold: _asDouble(map['low_stock_threshold']),
    notes: (map['notes'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((map['created_at'] as String?) ?? '') ??
        DateTime.now(),
    serialNumber: _emptyToNull(map['serial_number']),
    condition: _emptyToNull(map['condition']),
    assignedTo: _emptyToNull(map['assigned_to']),
    location: _emptyToNull(map['location']),
    purchaseDate: parseDateOnly(map['purchase_date']),
    warrantyUntil: parseDateOnly(map['warranty_until']),
  );

  /// Metadata keys are only present when set (see [Chemical.toMap]).
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'quantity': quantity,
    'initial_quantity': initialQuantity,
    'low_stock_threshold': lowStockThreshold,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    ...metadataMap(),
  };

  Map<String, dynamic> metadataMap() => {
    if ((serialNumber ?? '').isNotEmpty) 'serial_number': serialNumber,
    if ((condition ?? '').isNotEmpty) 'condition': condition,
    if ((assignedTo ?? '').isNotEmpty) 'assigned_to': assignedTo,
    if ((location ?? '').isNotEmpty) 'location': location,
    if (purchaseDate != null) 'purchase_date': formatDateOnly(purchaseDate!),
    if (warrantyUntil != null) 'warranty_until': formatDateOnly(warrantyUntil!),
  };
}

/// Optional GEAR-01 metadata captured by the apparatus forms and CSV import.
class ApparatusDetails {
  const ApparatusDetails({
    this.serialNumber,
    this.condition,
    this.assignedTo,
    this.location,
    this.purchaseDate,
    this.warrantyUntil,
  });

  factory ApparatusDetails.of(Apparatus item) => ApparatusDetails(
    serialNumber: item.serialNumber,
    condition: item.condition,
    assignedTo: item.assignedTo,
    location: item.location,
    purchaseDate: item.purchaseDate,
    warrantyUntil: item.warrantyUntil,
  );

  final String? serialNumber;
  final String? condition;
  final String? assignedTo;
  final String? location;
  final DateTime? purchaseDate;
  final DateTime? warrantyUntil;

  bool get isEmpty =>
      _emptyToNull(serialNumber) == null &&
      _emptyToNull(condition) == null &&
      _emptyToNull(assignedTo) == null &&
      _emptyToNull(location) == null &&
      purchaseDate == null &&
      warrantyUntil == null;

  /// Full column map for updates; nulls clear a column on the server.
  Map<String, dynamic> toChanges() => {
    'serial_number': _emptyToNull(serialNumber),
    'condition': _emptyToNull(condition?.toLowerCase()),
    'assigned_to': _emptyToNull(assignedTo),
    'location': _emptyToNull(location),
    'purchase_date': purchaseDate == null
        ? null
        : formatDateOnly(purchaseDate!),
    'warranty_until': warrantyUntil == null
        ? null
        : formatDateOnly(warrantyUntil!),
  };

  bool sameAs(ApparatusDetails other) {
    final mine = toChanges();
    final theirs = other.toChanges();
    for (final key in mine.keys) {
      if (mine[key] != theirs[key]) return false;
    }
    return true;
  }
}

class ConsumptionLog {
  const ConsumptionLog({
    required this.id,
    required this.itemId,
    required this.itemType,
    required this.action,
    required this.amount,
    required this.note,
    required this.loggedAt,
    required this.createdAt,
    this.operationId,
  });

  final String id;
  final String itemId;
  final ItemKind itemType;
  final InventoryAction action;
  final double amount;
  final String note;
  final DateTime loggedAt;
  final DateTime createdAt;
  final String? operationId;

  factory ConsumptionLog.fromMap(Map<String, dynamic> map) => ConsumptionLog(
    id: map['id'] as String,
    itemId: map['item_id'] as String,
    itemType: map['item_type'] == 'apparatus'
        ? ItemKind.apparatus
        : ItemKind.chemical,
    action: InventoryAction.values.firstWhere(
      (value) => value.name == map['action'],
      orElse: () => InventoryAction.consume,
    ),
    amount: _asDouble(map['amount']),
    note: (map['note'] as String?) ?? '',
    loggedAt:
        DateTime.tryParse((map['logged_at'] as String?) ?? '') ??
        DateTime.now(),
    createdAt:
        DateTime.tryParse((map['created_at'] as String?) ?? '') ??
        DateTime.now(),
    operationId: map['operation_id'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'item_id': itemId,
    'item_type': itemType.name,
    'action': action.name,
    'amount': amount,
    'note': note,
    'logged_at': loggedAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    if (operationId != null) 'operation_id': operationId,
  };
}

/// How long after recording a change it can still be undone (UX-04).
const undoWindow = Duration(days: 7);

/// Whether [log] is recent enough to be reversed from the app.
bool isUndoable(ConsumptionLog log, {DateTime? now}) =>
    (now ?? DateTime.now()).difference(log.createdAt) <= undoWindow;

/// A reversed inventory action. The original log entry is deleted (exactly
/// what the web app's undo does) and this record keeps the audit trail honest.
class InventoryReversal {
  const InventoryReversal({
    required this.id,
    required this.itemId,
    required this.itemType,
    required this.action,
    required this.amount,
    required this.reversedAt,
    this.originalLogId,
    this.originalLoggedAt,
    this.originalNote = '',
    this.reason = '',
    this.operationId,
    this.localOnly = false,
  });

  final String id;
  final String itemId;
  final ItemKind itemType;
  final InventoryAction action;
  final double amount;
  final DateTime reversedAt;
  final String? originalLogId;
  final DateTime? originalLoggedAt;
  final String originalNote;
  final String reason;
  final String? operationId;

  /// True when the server does not have the reversal table yet and the
  /// record only exists on this device.
  final bool localOnly;

  factory InventoryReversal.fromMap(Map<String, dynamic> map) =>
      InventoryReversal(
        id: map['id'] as String,
        itemId: map['item_id'] as String,
        itemType: map['item_type'] == 'apparatus'
            ? ItemKind.apparatus
            : ItemKind.chemical,
        action: InventoryAction.values.firstWhere(
          (value) => value.name == map['action'],
          orElse: () => InventoryAction.consume,
        ),
        amount: _asDouble(map['amount']),
        reversedAt:
            DateTime.tryParse((map['reversed_at'] as String?) ?? '') ??
            DateTime.now(),
        originalLogId: map['original_log_id'] as String?,
        originalLoggedAt: DateTime.tryParse(
          (map['original_logged_at'] as String?) ?? '',
        ),
        originalNote: (map['original_note'] as String?) ?? '',
        reason: (map['reason'] as String?) ?? '',
        operationId: map['operation_id'] as String?,
        localOnly: map['local_only'] == true,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'item_id': itemId,
    'item_type': itemType.name,
    'action': action.name,
    'amount': amount,
    'reversed_at': reversedAt.toIso8601String(),
    'original_log_id': originalLogId,
    'original_logged_at': originalLoggedAt?.toIso8601String(),
    'original_note': originalNote,
    'reason': reason,
    'operation_id': operationId,
    if (localOnly) 'local_only': true,
  };
}

/// A loan of one or more pieces of an apparatus to a person (GEAR-02).
/// Stored in the additive `apparatus_checkouts` table.
class ApparatusCheckout {
  const ApparatusCheckout({
    required this.id,
    required this.apparatusId,
    required this.quantity,
    required this.checkedOutAt,
    this.returnedQuantity = 0,
    this.person = '',
    this.note = '',
    this.returnNote = '',
    this.dueAt,
    this.returnedAt,
    this.operationId,
  });

  final String id;
  final String apparatusId;
  final double quantity;
  final double returnedQuantity;
  final String person;
  final String note;
  final String returnNote;
  final DateTime checkedOutAt;
  final DateTime? dueAt;
  final DateTime? returnedAt;
  final String? operationId;

  /// Pieces still out.
  double get outstanding {
    final left = quantity - returnedQuantity;
    return left < 0 ? 0 : left;
  }

  bool get isOpen => returnedAt == null && outstanding > 0;

  bool isOverdue({DateTime? now}) =>
      isOpen && dueAt != null && dueAt!.isBefore(now ?? DateTime.now());

  ApparatusCheckout copyWith({
    double? returnedQuantity,
    String? returnNote,
    DateTime? returnedAt,
    bool clearReturnedAt = false,
  }) => ApparatusCheckout(
    id: id,
    apparatusId: apparatusId,
    quantity: quantity,
    checkedOutAt: checkedOutAt,
    returnedQuantity: returnedQuantity ?? this.returnedQuantity,
    person: person,
    note: note,
    returnNote: returnNote ?? this.returnNote,
    dueAt: dueAt,
    returnedAt: clearReturnedAt ? null : (returnedAt ?? this.returnedAt),
    operationId: operationId,
  );

  factory ApparatusCheckout.fromMap(Map<String, dynamic> map) =>
      ApparatusCheckout(
        id: map['id'] as String,
        apparatusId: map['apparatus_id'] as String,
        quantity: _asDouble(map['quantity']),
        returnedQuantity: _asDouble(map['returned_quantity']),
        person: (map['person'] as String?) ?? '',
        note: (map['note'] as String?) ?? '',
        returnNote: (map['return_note'] as String?) ?? '',
        checkedOutAt: _asLocalTime(map['checked_out_at']) ?? DateTime.now(),
        dueAt: _asLocalTime(map['due_at']),
        returnedAt: _asLocalTime(map['returned_at']),
        operationId: map['operation_id'] as String?,
      );

  /// Timestamps travel as UTC ISO strings so the cache and Supabase agree.
  Map<String, dynamic> toMap() => {
    'id': id,
    'apparatus_id': apparatusId,
    'quantity': quantity,
    'returned_quantity': returnedQuantity,
    'person': person,
    'note': note,
    'return_note': returnNote,
    'checked_out_at': checkedOutAt.toUtc().toIso8601String(),
    'due_at': dueAt?.toUtc().toIso8601String(),
    'returned_at': returnedAt?.toUtc().toIso8601String(),
    'operation_id': operationId,
  };

  static DateTime? _asLocalTime(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

/// Kind of service task tracked for an apparatus (GEAR-03).
enum ServiceKind {
  maintenance('maintenance', 'Maintenance'),
  calibration('calibration', 'Calibration');

  const ServiceKind(this.value, this.label);

  final String value;
  final String label;

  static ServiceKind parse(Object? value) => switch (value?.toString()) {
    'calibration' => ServiceKind.calibration,
    _ => ServiceKind.maintenance,
  };
}

/// Suggested outcomes offered when a task is completed.
const serviceResults = ['pass', 'adjusted', 'fail', 'serviced'];

/// One maintenance or calibration task for an apparatus, stored in the
/// additive `apparatus_services` table (GEAR-03). Scheduled tasks have a
/// [dueAt] and no [completedAt]; completing fills in the rest.
class ApparatusService {
  const ApparatusService({
    required this.id,
    required this.apparatusId,
    required this.kind,
    required this.createdAt,
    this.title = '',
    this.note = '',
    this.dueAt,
    this.completedAt,
    this.performedBy = '',
    this.result = '',
    this.operationId,
  });

  final String id;
  final String apparatusId;
  final ServiceKind kind;
  final String title;
  final String note;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String performedBy;
  final String result;
  final String? operationId;
  final DateTime createdAt;

  bool get isDone => completedAt != null;

  bool get isOpen => completedAt == null;

  /// Title shown in lists: the custom title or the kind.
  String get displayTitle => title.isEmpty ? kind.label : title;

  /// How urgent an open task is: `expired` = overdue, `expiringSoon` = due
  /// within [soonDays], `ok` otherwise, `none` when done or undated.
  ExpiryState dueState({DateTime? now, int soonDays = 14}) {
    final due = dueAt;
    if (!isOpen || due == null) return ExpiryState.none;
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final days = DateTime(due.year, due.month, due.day).difference(today).inDays;
    if (days < 0) return ExpiryState.expired;
    return days <= soonDays ? ExpiryState.expiringSoon : ExpiryState.ok;
  }

  bool isOverdue({DateTime? now}) =>
      dueState(now: now) == ExpiryState.expired;

  ApparatusService copyWith({
    String? title,
    String? note,
    DateTime? dueAt,
    DateTime? completedAt,
    String? performedBy,
    String? result,
    bool clearCompletedAt = false,
  }) => ApparatusService(
    id: id,
    apparatusId: apparatusId,
    kind: kind,
    createdAt: createdAt,
    title: title ?? this.title,
    note: note ?? this.note,
    dueAt: dueAt ?? this.dueAt,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    performedBy: performedBy ?? this.performedBy,
    result: result ?? this.result,
    operationId: operationId,
  );

  factory ApparatusService.fromMap(Map<String, dynamic> map) =>
      ApparatusService(
        id: map['id'] as String,
        apparatusId: map['apparatus_id'] as String,
        kind: ServiceKind.parse(map['kind']),
        title: (map['title'] as String?) ?? '',
        note: (map['note'] as String?) ?? '',
        dueAt: ApparatusCheckout._asLocalTime(map['due_at']),
        completedAt: ApparatusCheckout._asLocalTime(map['completed_at']),
        performedBy: (map['performed_by'] as String?) ?? '',
        result: (map['result'] as String?) ?? '',
        operationId: map['operation_id'] as String?,
        createdAt:
            ApparatusCheckout._asLocalTime(map['created_at']) ?? DateTime.now(),
      );

  /// Timestamps travel as UTC ISO strings so the cache and Supabase agree.
  Map<String, dynamic> toMap() => {
    'id': id,
    'apparatus_id': apparatusId,
    'kind': kind.value,
    'title': title,
    'note': note,
    'due_at': dueAt?.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'performed_by': performedBy,
    'result': result,
    'operation_id': operationId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

/// Whether a queued change is still waiting for a connection or needs the
/// user to look at it (SYNC-01).
enum PendingStatus { pending, failed }

class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.userId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.status = PendingStatus.pending,
    this.label,
    this.lastAttemptAt,
  });

  final String id;
  final String userId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final PendingStatus status;
  final String? label;
  final DateTime? lastAttemptAt;

  bool get isFailed => status == PendingStatus.failed;

  /// The inventory item this change belongs to, when it has one.
  String? get itemId =>
      (payload['item_id'] ?? payload['apparatus_id'] ?? payload['id'])
          as String?;

  /// Human-readable summary shown in the sync center.
  String get description {
    final saved = label;
    if (saved != null && saved.isNotEmpty) return saved;
    return switch (type) {
      'add_chemical' => 'Add chemical ${payload['name'] ?? ''}'.trim(),
      'add_apparatus' => 'Add apparatus ${payload['name'] ?? ''}'.trim(),
      'update_item' => 'Update item',
      'inventory_action' =>
        '${_capitalize(payload['action']?.toString() ?? 'change')} '
            '${formatQuantity(_asDouble(payload['amount']))}',
      'undo_action' => 'Undo a recorded change',
      'checkout_apparatus' =>
        'Check out apparatus to ${payload['person'] ?? ''}'.trim(),
      'return_apparatus' => 'Return apparatus',
      'schedule_service' =>
        'Schedule ${ServiceKind.parse(payload['kind']).label.toLowerCase()}',
      'complete_service' => 'Complete service task',
      _ => type.replaceAll('_', ' '),
    };
  }

  Map<String, Object?> toDatabase() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'payload': jsonEncode(payload),
    'created_at': createdAt.toIso8601String(),
    'attempts': attempts,
    'last_error': lastError,
    'status': status.name,
    'label': label,
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
  };

  factory PendingOperation.fromDatabase(Map<String, Object?> row) =>
      PendingOperation(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        type: row['type']! as String,
        payload: jsonDecode(row['payload']! as String) as Map<String, dynamic>,
        createdAt: DateTime.parse(row['created_at']! as String),
        attempts: (row['attempts'] as int?) ?? 0,
        lastError: row['last_error'] as String?,
        status: row['status'] == 'failed'
            ? PendingStatus.failed
            : PendingStatus.pending,
        label: row['label'] as String?,
        lastAttemptAt: DateTime.tryParse(
          (row['last_attempt_at'] as String?) ?? '',
        ),
      );
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

DateTime localDayAtNoon(DateTime value) =>
    DateTime(value.year, value.month, value.day, 12);

String localDayKey(DateTime value) =>
    DateFormat('yyyy-MM-dd').format(value.toLocal());
