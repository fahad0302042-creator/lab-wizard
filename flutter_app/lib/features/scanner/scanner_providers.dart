import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'domain/recent_scan.dart';

/// Device-local scan history for the signed-in user (SCAN-01).
final recentScansProvider =
    NotifierProvider<RecentScansController, List<RecentScan>>(
      RecentScansController.new,
    );

/// Key under which a user's history is kept in shared preferences.
String recentScansKey(String? userId) => 'scans.${userId ?? 'anonymous'}';

/// Serialises a history for shared preferences.
String encodeRecentScans(List<RecentScan> scans) =>
    jsonEncode([for (final scan in scans) scan.toJson()]);

/// Parses what [encodeRecentScans] wrote; anything unreadable yields an empty
/// history instead of an error.
List<RecentScan> decodeRecentScans(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map<String, dynamic>) RecentScan.fromJson(entry),
    ];
  } on FormatException {
    return const [];
  }
}

class RecentScansController extends Notifier<List<RecentScan>> {
  String _key = recentScansKey(null);

  @override
  List<RecentScan> build() {
    final userId = ref.watch(authProvider.select((value) => value.user?.id));
    _key = recentScansKey(userId);
    unawaited(_restore(_key));
    return const [];
  }

  Future<void> _restore(String key) async {
    final preferences = await SharedPreferences.getInstance();
    if (!ref.mounted || key != _key) return;
    final stored = decodeRecentScans(preferences.getString(key));
    if (stored.isEmpty) return;
    // Scans recorded while the history was still loading stay in front.
    final current = state;
    final seen = {for (final scan in current) scan.dedupeKey};
    state = [
      ...current,
      ...stored.where((scan) => !seen.contains(scan.dedupeKey)),
    ].take(recentScansLimit).toList(growable: false);
  }

  /// Adds a scan to the front of the history and persists it.
  Future<void> record(RecentScan scan) async {
    state = pushRecentScan(state, scan);
    await _persist();
  }

  /// Forgets the whole history of the current user on this device.
  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    final key = _key;
    final preferences = await SharedPreferences.getInstance();
    if (!ref.mounted || key != _key) return;
    // Always write the latest state so overlapping writes cannot regress it.
    final snapshot = state;
    if (snapshot.isEmpty) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, encodeRecentScans(snapshot));
    }
  }
}
