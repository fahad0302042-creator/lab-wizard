import 'dart:convert';

/// Conflict handling (SYNC-04).
///
/// A queued or live change conflicts with the server when the rows it
/// touches no longer look the way this device last saw them:
///
/// * [ConflictKind.changed] — a field this edit changes was also changed on
///   the server after the edit was made here. Updates only ever send the
///   fields that actually changed and are applied on the condition that
///   those fields still hold the values this device based the edit on, so
///   newer, unrelated data is never overwritten.
/// * [ConflictKind.deleted] — the item is gone from the server.
/// * [ConflictKind.stock] — the server has less stock than the change
///   needs (a consume/damage entry queued against a stale quantity, or an
///   undo the server can no longer honour).
enum ConflictKind { changed, deleted, stock }

/// What the user can do about a conflict.
enum ConflictResolution {
  /// Send the edit anyway, overwriting the conflicting fields.
  keepMine,

  /// Drop the conflicting fields and send what is left (nothing left means
  /// the change is discarded).
  useServer,

  /// Consume/damage only what the server still has.
  useAvailable,

  /// Drop the change on this device.
  discard,
}

/// One field that both sides changed.
class FieldConflict {
  const FieldConflict({
    required this.field,
    required this.base,
    required this.local,
    required this.server,
  });

  final String field;

  /// The value this device based its edit on.
  final Object? base;

  /// What this device wants to write.
  final Object? local;

  /// What the server has now.
  final Object? server;

  Map<String, dynamic> toJson() => {
    'field': field,
    'base': base,
    'local': local,
    'server': server,
  };

  static FieldConflict fromJson(Map<String, dynamic> json) => FieldConflict(
    field: json['field'] as String,
    base: json['base'],
    local: json['local'],
    server: json['server'],
  );

  String get label => fieldLabel(field);

  String get description =>
      '$label is now ${describeValue(server)} on the server '
      '(yours: ${describeValue(local)})';
}

class SyncConflict {
  const SyncConflict({
    required this.kind,
    required this.detectedAt,
    this.fields = const [],
    this.available,
    this.requested,
    this.unit,
    this.partialAllowed = false,
  });

  final ConflictKind kind;
  final DateTime detectedAt;

  /// Fields changed on both sides ([ConflictKind.changed]).
  final List<FieldConflict> fields;

  /// Stock the server still has ([ConflictKind.stock]).
  final double? available;

  /// Stock the change needs ([ConflictKind.stock]).
  final double? requested;
  final String? unit;

  /// Whether [ConflictResolution.useAvailable] makes sense (consuming part
  /// of a request does; undoing part of an undo does not).
  final bool partialAllowed;

  factory SyncConflict.changed(List<FieldConflict> fields, {DateTime? at}) =>
      SyncConflict(
        kind: ConflictKind.changed,
        fields: fields,
        detectedAt: at ?? DateTime.now(),
      );

  factory SyncConflict.deleted({DateTime? at}) =>
      SyncConflict(kind: ConflictKind.deleted, detectedAt: at ?? DateTime.now());

  factory SyncConflict.stock({
    required double available,
    required double requested,
    String? unit,
    bool partialAllowed = false,
    DateTime? at,
  }) => SyncConflict(
    kind: ConflictKind.stock,
    available: available,
    requested: requested,
    unit: unit,
    partialAllowed: partialAllowed,
    detectedAt: at ?? DateTime.now(),
  );

  /// The resolutions offered for this conflict, in display order.
  List<ConflictResolution> get resolutions => switch (kind) {
    ConflictKind.changed => const [
      ConflictResolution.useServer,
      ConflictResolution.keepMine,
      ConflictResolution.discard,
    ],
    ConflictKind.deleted => const [ConflictResolution.discard],
    ConflictKind.stock =>
      partialAllowed && (available ?? 0) > 0
          ? const [ConflictResolution.useAvailable, ConflictResolution.discard]
          : const [ConflictResolution.discard],
  };

  String _amount(double? value) =>
      '${_formatNumber(value ?? 0)}${(unit ?? '').isEmpty ? '' : ' $unit'}';

  /// One or two sentences for the sync center card.
  String get explanation => switch (kind) {
    ConflictKind.changed =>
      'Changed on the server after your edit: '
          '${fields.map((field) => field.description).join('; ')}.',
    ConflictKind.deleted =>
      'This item was deleted on the server, so the change cannot be '
          'applied.',
    ConflictKind.stock =>
      'The server has only ${_amount(available)} left; this change needs '
          '${_amount(requested)}.',
  };

  /// Short form used as the error line and in exceptions.
  String get summary => switch (kind) {
    ConflictKind.changed =>
      'Changed on the server since you loaded it: '
          '${fields.map((field) => field.label).join(', ')}.',
    ConflictKind.deleted => 'Deleted on the server.',
    ConflictKind.stock =>
      'Only ${_amount(available)} available on the server.',
  };

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'detected_at': detectedAt.toIso8601String(),
    'fields': [for (final field in fields) field.toJson()],
    'available': available,
    'requested': requested,
    'unit': unit,
    'partial_allowed': partialAllowed,
  };

  String encode() => jsonEncode(toJson());

  static SyncConflict? decode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  static SyncConflict fromJson(Map<String, dynamic> json) {
    final kind = ConflictKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => ConflictKind.changed,
    );
    final fields = json['fields'];
    return SyncConflict(
      kind: kind,
      detectedAt:
          DateTime.tryParse(json['detected_at']?.toString() ?? '') ??
          DateTime.now(),
      fields: [
        if (fields is List)
          for (final field in fields)
            if (field is Map)
              FieldConflict.fromJson(Map<String, dynamic>.from(field)),
      ],
      available: (json['available'] as num?)?.toDouble(),
      requested: (json['requested'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      partialAllowed: json['partial_allowed'] == true,
    );
  }
}

/// Thrown by live (online) updates that hit a conflict, so the form can
/// offer the same choices as the sync center.
class ItemConflictException implements Exception {
  const ItemConflictException(this.conflict);

  final SyncConflict conflict;

  @override
  String toString() => conflict.summary;
}

/// Whether two column values mean the same thing. Numbers compare by value
/// (the server returns `5` for `5.0`), empty text equals null, and lists
/// compare as sets (hazard classes have no order).
bool valuesMatch(Object? a, Object? b) {
  if (a == null && b == null) return true;
  if (a is String && a.isEmpty && b == null) return true;
  if (b is String && b.isEmpty && a == null) return true;
  if (a is num && b is num) return (a - b).abs() < 1e-9;
  if (a is num && b is String) return num.tryParse(b) == a;
  if (b is num && a is String) return num.tryParse(a) == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    final rest = [...b];
    for (final item in a) {
      final index = rest.indexWhere((other) => valuesMatch(item, other));
      if (index < 0) return false;
      rest.removeAt(index);
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!valuesMatch(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Turns a server error into a conflict when it describes one, otherwise
/// null. [requested] and [unit] describe the change that failed.
SyncConflict? conflictFromError(
  Object error, {
  double? requested,
  String? unit,
  bool partialAllowed = false,
}) {
  if (error is ItemConflictException) return error.conflict;
  final message = error.toString();
  final lower = message.toLowerCase();
  final stock = RegExp(
    r'insufficient stock: only ([0-9]+(?:\.[0-9]+)?) available',
    caseSensitive: false,
  ).firstMatch(message);
  if (stock != null) {
    return SyncConflict.stock(
      available: double.parse(stock.group(1)!),
      requested: requested ?? 0,
      unit: unit,
      partialAllowed: partialAllowed,
    );
  }
  final undo = RegExp(
    r'cannot undo: only ([0-9]+(?:\.[0-9]+)?) left of the ([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  ).firstMatch(message);
  if (undo != null) {
    return SyncConflict.stock(
      available: double.parse(undo.group(1)!),
      requested: double.parse(undo.group(2)!),
      unit: unit,
    );
  }
  if (lower.contains('item not found') ||
      lower.contains('not owned by the current user') ||
      lower.contains('violates foreign key constraint') ||
      (lower.contains('no rows') && lower.contains('returned')) ||
      lower.contains('pgrst116')) {
    return SyncConflict.deleted();
  }
  return null;
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Human labels for the columns an edit can touch.
String fieldLabel(String column) => switch (column) {
  'low_stock_threshold' => 'low-stock level',
  'cas_number' => 'CAS number',
  'expiry_date' => 'expiry date',
  'hazard_classes' => 'hazards',
  'serial_number' => 'serial number',
  'assigned_to' => 'assigned to',
  'purchase_date' => 'purchase date',
  'warranty_until' => 'warranty until',
  'initial_quantity' => 'starting quantity',
  _ => column.replaceAll('_', ' '),
};

/// Short rendering of a column value for explanations.
String describeValue(Object? value) {
  if (value == null || (value is String && value.isEmpty)) return 'empty';
  if (value is num) return _formatNumber(value.toDouble());
  if (value is List) return value.isEmpty ? 'empty' : value.join(', ');
  final text = value.toString();
  return text.length > 60 ? '“${text.substring(0, 57)}…”' : '“$text”';
}
