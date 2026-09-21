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
  );

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
  };
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
  });

  final String id;
  final String name;
  final String category;
  final double quantity;
  final double initialQuantity;
  final double lowStockThreshold;
  final String notes;
  final DateTime createdAt;

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
  }) => Apparatus(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    quantity: quantity ?? this.quantity,
    initialQuantity: initialQuantity ?? this.initialQuantity,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    notes: notes ?? this.notes,
    createdAt: createdAt,
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
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'quantity': quantity,
    'initial_quantity': initialQuantity,
    'low_stock_threshold': lowStockThreshold,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };
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
  String? get itemId => (payload['item_id'] ?? payload['id']) as String?;

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
