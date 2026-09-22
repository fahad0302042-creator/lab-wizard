import '../../inventory/domain/models.dart';
import 'scan_resolver.dart';

/// Upper bound of the device-local scan history per user.
const recentScansLimit = 30;

/// One entry of the scanner's history. Stored only on this device, under the
/// signed-in user's id, and never sent to the server.
class RecentScan {
  const RecentScan({
    required this.raw,
    required this.scannedAt,
    this.kind,
    this.itemId,
    this.name = '',
    this.subtitle = '',
  });

  /// A scan that matched an inventory item.
  factory RecentScan.found(ScanMatch match, String raw, DateTime scannedAt) =>
      RecentScan(
        raw: raw,
        scannedAt: scannedAt,
        kind: match.kind,
        itemId: match.id,
        name: match.name,
        subtitle: match.subtitle,
      );

  /// A scan that no item in the notebook carries.
  factory RecentScan.unknown(String raw, DateTime scannedAt) =>
      RecentScan(raw: raw, scannedAt: scannedAt);

  factory RecentScan.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String?;
    return RecentScan(
      raw: json['raw'] as String? ?? '',
      scannedAt:
          DateTime.tryParse(json['scannedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: kindName == null
          ? null
          : ItemKind.values.cast<ItemKind?>().firstWhere(
              (value) => value!.name == kindName,
              orElse: () => null,
            ),
      itemId: json['itemId'] as String?,
      name: json['name'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
    );
  }

  /// The text the camera read, trimmed; kept so an unknown code can still be
  /// inspected (or, later, attached to an item) after the moment has passed.
  final String raw;
  final DateTime scannedAt;
  final ItemKind? kind;
  final String? itemId;
  final String name;
  final String subtitle;

  bool get found => itemId != null && kind != null;

  /// Two history entries are the same when they point at the same item, or
  /// when they are the same unknown code.
  String get dedupeKey => found ? '${kind!.name}:$itemId' : 'raw:$raw';

  Map<String, dynamic> toJson() => {
    'raw': raw,
    'scannedAt': scannedAt.toIso8601String(),
    if (kind != null) 'kind': kind!.name,
    if (itemId != null) 'itemId': itemId,
    if (name.isNotEmpty) 'name': name,
    if (subtitle.isNotEmpty) 'subtitle': subtitle,
  };
}

/// Puts [scan] at the front of [history], drops older entries for the same
/// item or code, and trims the list to [recentScansLimit].
List<RecentScan> pushRecentScan(List<RecentScan> history, RecentScan scan) {
  final key = scan.dedupeKey;
  return [
    scan,
    ...history.where((entry) => entry.dedupeKey != key),
  ].take(recentScansLimit).toList(growable: false);
}
