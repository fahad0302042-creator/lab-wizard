import 'dart:async';

import 'package:flutter/services.dart';

import '../inventory/domain/models.dart';

/// Pure data computation and platform bridge for the Android Home Screen Widget.
class WidgetGateway {
  static const channelName = 'com.labwizard.lab_wizard/widget';
  static const MethodChannel channel = MethodChannel(channelName);

  static void Function(Uri uri)? _onDeepLink;

  /// Registers a handler for deep links triggered when tapping widget buttons.
  static void registerDeepLinkHandler(void Function(Uri uri) handler) {
    _onDeepLink = handler;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final uriString = call.arguments as String?;
        if (uriString != null) {
          final uri = Uri.tryParse(uriString);
          if (uri != null) _onDeepLink?.call(uri);
        }
      }
    });
  }

  /// Checks if the app was launched from a widget tap intent.
  static Future<Uri?> getInitialUri() async {
    try {
      final uriString = await channel.invokeMethod<String>('getInitialUri');
      if (uriString != null && uriString.isNotEmpty) {
        return Uri.tryParse(uriString);
      }
    } catch (_) {
      // Platform channels may throw in tests or unsupported environments.
    }
    return null;
  }

  /// Sends the latest inventory and consumption stats to the Android widget.
  static Future<bool> updateWidget({
    required String labName,
    required List<Chemical> chemicals,
    required List<Apparatus> apparatus,
    required List<ConsumptionLog> logs,
    DateTime? now,
  }) async {
    final payload = computeConsumptionWidgetData(
      labName: labName,
      chemicals: chemicals,
      apparatus: apparatus,
      logs: logs,
      now: now,
    );
    try {
      final success = await channel.invokeMethod<bool>('updateWidget', payload);
      return success ?? true;
    } catch (_) {
      return false;
    }
  }
}

/// Pure calculation of today's consumption payload for the home screen widget.
Map<String, dynamic> computeConsumptionWidgetData({
  required String labName,
  required List<Chemical> chemicals,
  required List<Apparatus> apparatus,
  required List<ConsumptionLog> logs,
  DateTime? now,
}) {
  final targetDate = now ?? DateTime.now();

  bool isToday(DateTime dt) {
    final l = dt.toLocal();
    final t = targetDate.toLocal();
    return l.year == t.year && l.month == t.month && l.day == t.day;
  }

  // Filter consumption & breakage logs from today
  final todayLogs = logs.where((l) {
    return isToday(l.loggedAt) &&
        (l.action == InventoryAction.consume ||
            l.action == InventoryAction.breakage);
  }).toList();

  // Aggregate consumed amounts per item
  final consumedPerItem = <String, double>{};
  final kindPerItem = <String, ItemKind>{};

  for (final log in todayLogs) {
    consumedPerItem.update(
      log.itemId,
      (current) => current + log.amount,
      ifAbsent: () => log.amount,
    );
    kindPerItem[log.itemId] = log.itemType;
  }

  // Sort by consumed amount descending
  final sortedItemIds = consumedPerItem.keys.toList()
    ..sort((a, b) => consumedPerItem[b]!.compareTo(consumedPerItem[a]!));

  final totalItemsUsed = sortedItemIds.length;
  final totalEvents = todayLogs.length;

  final todayHeader = totalItemsUsed == 0
      ? "TODAY'S CONSUMPTION"
      : 'TODAY: $totalItemsUsed item${totalItemsUsed == 1 ? '' : 's'} ($totalEvents use${totalEvents == 1 ? '' : 's'})';

  // Determine Flaskie's dynamic information cards (1 per click)
  final criticalChemical = chemicals
      .where(
        (c) =>
            c.stockState == StockState.empty || c.stockState == StockState.low,
      )
      .firstOrNull;
  final criticalApparatus = apparatus
      .where(
        (a) =>
            a.stockState == StockState.empty || a.stockState == StockState.low,
      )
      .firstOrNull;

  final cleanLabName = labName.trim().isEmpty ? 'Lab Wizard' : labName.trim();
  final List<String> infoCards = [];

  // Card 0: Critical stock alert or health confirmation
  if (criticalChemical != null) {
    infoCards.add('Low on ${criticalChemical.name}! (${formatQuantity(criticalChemical.quantity)} ${criticalChemical.unit} left)');
  } else if (criticalApparatus != null) {
    infoCards.add('Low on ${criticalApparatus.name}! (${criticalApparatus.quantity.toInt()} left)');
  } else {
    infoCards.add('All inventory stock healthy ✨');
  }

  // Card 1: Today's consumption stats
  if (totalItemsUsed > 0) {
    infoCards.add('$totalItemsUsed item${totalItemsUsed == 1 ? '' : 's'} used today ($totalEvents logs)');
  } else {
    infoCards.add('No usage logged today yet 🧪');
  }

  // Card 2: Shelf counts
  infoCards.add('Shelf: ${chemicals.length} chems • ${apparatus.length} gear');

  // Card 3: Active lab name
  infoCards.add('Lab: $cleanLabName');

  // Card 4: Quick action tip
  infoCards.add('Tip: Tap [📷 Scan] to log in seconds');

  final data = <String, dynamic>{
    'lab_name': cleanLabName,
    'today_header': todayHeader,
    'flaskie_speech': infoCards[0],
    'info_count': infoCards.length,
    'total_chems': chemicals.length,
    'total_apparatus': apparatus.length,
  };

  for (var i = 0; i < infoCards.length; i++) {
    data['info_$i'] = infoCards[i];
  }

  // Populate top 3 items
  for (var i = 0; i < 3; i++) {
    final prefix = 'item_${i + 1}';
    if (i < sortedItemIds.length) {
      final itemId = sortedItemIds[i];
      final used = consumedPerItem[itemId]!;
      final kind = kindPerItem[itemId]!;

      String name = '';
      String unit = '';
      double left = 0;

      if (kind == ItemKind.chemical) {
        final chem = chemicals.where((c) => c.id == itemId).firstOrNull;
        name = chem?.name ?? 'Chemical';
        unit = chem?.unit ?? '';
        left = chem?.quantity ?? 0;
      } else {
        final app = apparatus.where((a) => a.id == itemId).firstOrNull;
        name = app?.name ?? 'Apparatus';
        unit = 'pcs';
        left = app?.quantity.toDouble() ?? 0;
      }

      data['${prefix}_id'] = itemId;
      data['${prefix}_name'] = name;
      data['${prefix}_used'] = '-${formatQuantity(used)} $unit'.trim();
      data['${prefix}_remaining'] = '(${formatQuantity(left)} $unit left)'
          .trim();
    } else {
      data['${prefix}_id'] = '';
      data['${prefix}_name'] = '';
      data['${prefix}_used'] = '';
      data['${prefix}_remaining'] = '';
    }
  }

  return data;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
