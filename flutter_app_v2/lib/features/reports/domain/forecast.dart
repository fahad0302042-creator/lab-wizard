/// How long the stock on the shelf will last, judged from what has actually
/// been logged.
///
/// This is the one question a paper register cannot answer, and the only one
/// the app is in a position to answer without asking for more input: every
/// consume and breakage already carries a timestamp, and the report code
/// already treats `consume` and `breakage` as usage. So a rate is a
/// consequence of data the lab already keeps, not a new chore.
///
/// Deliberately pure — no providers, no database, no clock. `now` is passed in
/// so the arithmetic can be tested without a device, exactly like
/// `buildMonthlyReport`.
library;

import '../../inventory/domain/models.dart';

/// How much history a rate is judged over.
///
/// Longer windows are steadier; shorter ones notice a busy week. The window is
/// fixed rather than adaptive so two items can be compared honestly: a
/// rate measured over 30 days and one measured over 300 are not the same claim.
const int kForecastWindowDays = 90;

/// Below this many days of history we decline to forecast at all.
///
/// A rate needs a denominator. One week of logging, extrapolated to a
/// "days remaining" figure, is a guess wearing a number's clothes — and a wrong
/// reorder date is worse than no reorder date, because someone acts on it.
const int kMinimumHistoryDays = 21;

/// Below this many separate usage events we decline to forecast.
///
/// Two big sessions in a fortnight say almost nothing about next month. Five
/// distinct days of usage spread across the window is the point where a mean is
/// describing a habit rather than an accident.
const int kMinimumUsageDays = 5;

/// How confident a forecast is, in plain language. Kept as an enum rather than
/// a percentage: a 40% confidence bar invites someone to trust the number, and
/// the whole point of this module is to be honest about what it does not know.
enum ForecastConfidence {
  /// Judged on a full window with steady usage. Worth planning around.
  steady,

  /// Enough to state a rate, but the usage was lumpy or the window is short.
  rough,

  /// Not enough history. No number is shown.
  none,
}

/// One item's runway.
class Forecast {
  const Forecast({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantityOnHand,
    required this.perDay,
    required this.daysLeft,
    this.confidence = ForecastConfidence.none,
    this.usedInWindow = 0,
    this.usageDays = 0,
    this.windowDays = 0,
  });

  final String id;
  final String name;
  final String unit;
  final double quantityOnHand;

  /// Average usage per day over the measured window. Zero when nothing was used.
  final double perDay;

  /// Days of stock remaining at the measured rate. Null when incalculable —
  /// either nothing is being used, or there is not enough history to say.
  final double? daysLeft;

  final ForecastConfidence confidence;

  /// Total consumed inside the window, for showing the working.
  final double usedInWindow;

  /// Distinct days with at least one usage event. Drives the confidence rule.
  final int usageDays;

  /// How many days the window actually covered, which is shorter than
  /// [kForecastWindowDays] on a young install.
  final int windowDays;

  /// True when we are declining to give a date.
  bool get declined => confidence == ForecastConfidence.none;

  /// True when a figure exists and the shelf runs out inside a reorder horizon.
  bool get soon => daysLeft != null && daysLeft! <= 30;
}

/// Everything the dashboard needs to say "here is what will run out".
class ForecastBoard {
  const ForecastBoard({
    required this.items,
    required this.historyDays,
    required this.hasEnoughHistory,
  });

  /// One entry per item that has a runway worth showing, soonest first.
  final List<Forecast> items;

  /// Length of the available log history, in days. Shown to the user so the
  /// app can say *why* it is quiet on a young install instead of looking broken.
  final int historyDays;

  /// False until [kMinimumHistoryDays] of logs exist. When false, the board
  /// says so rather than displaying an empty list that reads as "all fine".
  final bool hasEnoughHistory;

  /// Items expected to run out within a month, soonest first.
  List<Forecast> get runningOut => items.where((f) => f.soon).toList();

  bool get isEmpty => items.isEmpty;
}

/// Builds the runway board from the logs already in memory.
///
/// [now] is injected so tests do not depend on the wall clock.
ForecastBoard buildForecastBoard({
  required List<Chemical> chemicals,
  required List<Apparatus> apparatus,
  required List<ConsumptionLog> logs,
  required DateTime now,
}) {
  final windowStart = now.subtract(const Duration(days: kForecastWindowDays));

  // Usage is consume and breakage; restock is the opposite direction and must
  // never enter a rate, or an item would appear to drain faster every time it
  // was topped up.
  final usage = logs
      .where((log) => log.action != InventoryAction.restock)
      .where((log) => !log.loggedAt.isBefore(windowStart))
      .where((log) => !log.loggedAt.isAfter(now))
      .toList();

  // Age of the log set: from the oldest thing ever recorded to `now`. This is
  // what decides whether a rate is trustworthy, and it is not the same as the
  // window length — a lab that installed yesterday has one day of history
  // however wide the window is.
  DateTime? oldest;
  for (final log in logs) {
    if (oldest == null || log.loggedAt.isBefore(oldest)) oldest = log.loggedAt;
  }
  final historyDays = oldest == null
      ? 0
      : now.difference(oldest).inDays.clamp(0, 1 << 20);
  final hasEnoughHistory = historyDays >= kMinimumHistoryDays;

  // The denominator: days the window actually covers. Using the full window on
  // a young install would divide real usage by a span that never happened and
  // silently understate the rate — the opposite of the loud direction, which is
  // the dangerous one for a reorder figure.
  final effectiveDays = historyDays.clamp(1, kForecastWindowDays);

  final used = <String, double>{};
  final daysWithUse = <String, Set<String>>{};
  for (final log in usage) {
    used.update(log.itemId, (v) => v + log.amount, ifAbsent: () => log.amount);
    daysWithUse
        .putIfAbsent(log.itemId, () => <String>{})
        .add(_dayKey(log.loggedAt));
  }

  final out = <Forecast>[];

  void consider({
    required String id,
    required String name,
    required String unit,
    required double quantity,
  }) {
    final total = used[id] ?? 0;
    final usageDays = daysWithUse[id]?.length ?? 0;

    // Nothing consumed: no rate, so no date. Not "infinite supply" — we have
    // simply never seen this item used, which is a different sentence and must
    // not be dressed up as a forecast.
    if (total <= 0 || usageDays < kMinimumUsageDays || !hasEnoughHistory) {
      return;
    }

    final perDay = total / effectiveDays;
    final daysLeft = quantity <= 0 ? 0.0 : quantity / perDay;

    // Lumpy usage: compare the busiest single day against the *median* day.
    //
    // The mean would not catch this. A reagent drawn down in one enormous
    // session is often booked across several days, which drags the mean day up
    // with it and hides the very spike we are looking for — measured that way,
    // a 900-unit day sitting among ten-unit days looked perfectly steady. The
    // median day ignores the spike entirely, so any single day more than three
    // median days says the pattern is a session, not a rhythm.
    final steady =
        _busiestDay(usage, id) <= _medianDay(usage, id) * 3 &&
        effectiveDays >= 45;

    out.add(
      Forecast(
        id: id,
        name: name,
        unit: unit,
        quantityOnHand: quantity,
        perDay: perDay,
        daysLeft: daysLeft,
        confidence: steady
            ? ForecastConfidence.steady
            : ForecastConfidence.rough,
        usedInWindow: total,
        usageDays: usageDays,
        windowDays: effectiveDays,
      ),
    );
  }

  for (final item in chemicals) {
    consider(
      id: item.id,
      name: item.name,
      unit: item.unit,
      quantity: item.quantity,
    );
  }
  for (final item in apparatus) {
    consider(
      id: item.id,
      name: item.name,
      unit: 'pcs',
      quantity: item.quantity,
    );
  }

  // Soonest first, and a known-empty item first of all. Ties break
  // alphabetically so the list does not jitter between rebuilds.
  out.sort((a, b) {
    final aDays = a.daysLeft ?? double.infinity;
    final bDays = b.daysLeft ?? double.infinity;
    if (aDays != bDays) return aDays.compareTo(bDays);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return ForecastBoard(
    items: out,
    historyDays: historyDays,
    hasEnoughHistory: hasEnoughHistory,
  );
}

/// One item's usage, totalled per calendar day inside the window.
Map<String, double> _perDay(List<ConsumptionLog> usage, String itemId) {
  final perDay = <String, double>{};
  for (final log in usage) {
    if (log.itemId != itemId) continue;
    perDay.update(
      _dayKey(log.loggedAt),
      (v) => v + log.amount,
      ifAbsent: () => log.amount,
    );
  }
  return perDay;
}

/// The largest single-day usage for one item inside the window.
double _busiestDay(List<ConsumptionLog> usage, String itemId) {
  final perDay = _perDay(usage, itemId);
  return perDay.values.fold<double>(0, (a, b) => a > b ? a : b);
}

/// The middle day's usage. Deliberately not the mean: see the confidence rule.
double _medianDay(List<ConsumptionLog> usage, String itemId) {
  final values = _perDay(usage, itemId).values.toList()..sort();
  if (values.isEmpty) return 0;
  final middle = values.length ~/ 2;
  // Even count: average the two middles so the measure has no bias.
  if (values.length.isEven) return (values[middle - 1] + values[middle]) / 2;
  return values[middle];
}

/// A local calendar day. Logs are stamped at noon local by the repository, so
/// this groups by the same day the user would name.
String _dayKey(DateTime at) {
  final local = at.toLocal();
  return '${local.year}-${local.month}-${local.day}';
}

/// The sentence under a runway figure.
///
/// Wording is built here, beside the arithmetic, for the same reason
/// `stockCaption` lives beside `jarMetrics`: so the number and the claim about
/// it cannot drift apart.
String runwayCaption(Forecast forecast) {
  final days = forecast.daysLeft;
  if (days == null) return 'not enough history to forecast';

  if (days <= 0) return 'empty now';
  if (days < 1) return 'less than a day left';

  final rounded = days.round();
  final basis = switch (forecast.confidence) {
    ForecastConfidence.steady => 'lasting',
    ForecastConfidence.rough => 'roughly',
    ForecastConfidence.none => '',
  };

  if (rounded == 1) return '$basis 1 day left';
  // Past a year the number stops meaning anything useful, and a fixed date is
  // more honest than "412 days".
  if (rounded > 365) return 'more than a year of stock';
  return '$basis $rounded days left';
}

/// Why a board is quiet, when it is. Null when there is something to show.
String? forecastSilence(ForecastBoard board) {
  if (!board.hasEnoughHistory) {
    final need = kMinimumHistoryDays - board.historyDays;
    final remaining = need == 1 ? '1 day' : '$need days';
    return 'Runway appears after $kMinimumHistoryDays days of logging — '
        '$remaining to go.';
  }
  if (board.isEmpty) {
    return 'No runway yet. It takes $kMinimumUsageDays logged uses over '
        '$kMinimumHistoryDays+ days before a rate means anything.';
  }
  return null;
}
