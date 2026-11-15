import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/inventory/domain/models.dart';
import 'package:lab_wizard_v2/features/reports/domain/forecast.dart';

/// A log stamped `daysAgo` before [now], at noon local like the repository.
///
/// The arithmetic is pure and takes `now`, so the tests can sit on a fixed
/// instant and the results will not rot.
ConsumptionLog _log({
  required String itemId,
  required double amount,
  required int daysAgo,
  required DateTime now,
  InventoryAction action = InventoryAction.consume,
  ItemKind kind = ItemKind.chemical,
}) {
  final day = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysAgo))
      .add(const Duration(hours: 12));
  return ConsumptionLog(
    id: '$itemId-$daysAgo-$amount',
    itemId: itemId,
    itemType: kind,
    action: action,
    amount: amount,
    note: '',
    loggedAt: day,
    createdAt: day,
  );
}

Chemical _chemical({
  required String id,
  required double quantity,
  String name = 'Reagent',
  String unit = 'mL',
}) => Chemical(
  id: id,
  name: name,
  formula: '',
  unit: unit,
  quantity: quantity,
  initialQuantity: 0,
  lowStockThreshold: 0,
  notes: '',
  qrCode: '',
  createdAt: DateTime(2020),
);

void main() {
  final now = DateTime(2026, 6, 30, 9);

  group('runway needs history before it will speak', () {
    test('a fresh install declines, and says why', () {
      // Ten uses crammed into the last three days. A naive rate would divide by
      // the full 90-day window, understate the drain, and hand someone a
      // reorder date that is far too comfortable.
      final logs = [
        for (var i = 0; i < 10; i++)
          _log(itemId: 'a', amount: 100, daysAgo: i % 3, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 2000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.hasEnoughHistory, isFalse);
      expect(board.items, isEmpty);
      expect(forecastSilence(board), contains('21 days of logging'));
    });

    test('the same usage is believed once the history is old enough', () {
      // Identical quantity and event count, but spread across a real span.
      final logs = [
        for (var i = 0; i < 10; i++)
          _log(itemId: 'a', amount: 100, daysAgo: 3 + i * 7, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 2000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.hasEnoughHistory, isTrue);
      expect(board.items, hasLength(1));
      expect(board.items.single.daysLeft, isNotNull);
    });

    test('too few separate days of use is not a rate', () {
      // Two sessions, plenty of history. A hundred units in two days says
      // nothing about next month.
      final logs = [
        _log(itemId: 'a', amount: 500, daysAgo: 40, now: now),
        _log(itemId: 'a', amount: 500, daysAgo: 60, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 2000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.hasEnoughHistory, isTrue);
      expect(board.items, isEmpty);
      expect(forecastSilence(board), contains('No runway yet'));
    });
  });

  group('the rate is built from usage only', () {
    test('restocking never enters the rate', () {
      // An item topped up every week must not look like it drains faster for it.
      final usage = [
        for (var i = 0; i < 6; i++)
          _log(itemId: 'a', amount: 50, daysAgo: 5 + i * 12, now: now),
      ];
      final restocks = [
        for (var i = 0; i < 6; i++)
          _log(
            itemId: 'a',
            amount: 500,
            daysAgo: 2 + i * 12,
            now: now,
            action: InventoryAction.restock,
          ),
      ];
      final withRestocks = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 1000)],
        apparatus: const [],
        logs: [...usage, ...restocks],
        now: now,
      );
      final without = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 1000)],
        apparatus: const [],
        logs: usage,
        now: now,
      );

      expect(
        withRestocks.items.single.perDay,
        closeTo(without.items.single.perDay, 1e-9),
      );
      expect(withRestocks.items.single.usedInWindow, 300);
    });

    test('breakage counts as usage, because the piece is gone', () {
      final logs = [
        for (var i = 0; i < 6; i++)
          _log(
            itemId: 'g',
            amount: 2,
            daysAgo: 5 + i * 10,
            now: now,
            action: InventoryAction.breakage,
            kind: ItemKind.apparatus,
          ),
      ];
      final board = buildForecastBoard(
        chemicals: const [],
        apparatus: [
          Apparatus(
            id: 'g',
            name: 'Beakers',
            category: 'glassware',
            quantity: 20,
            initialQuantity: 0,
            lowStockThreshold: 0,
            notes: '',
            createdAt: DateTime(2020),
          ),
        ],
        logs: logs,
        now: now,
      );

      expect(board.items, hasLength(1));
      expect(board.items.single.usedInWindow, 12);
      expect(board.items.single.unit, 'pcs');
    });

    test('logs outside the window do not count toward the rate', () {
      final logs = [
        // Inside the window.
        for (var i = 0; i < 6; i++)
          _log(itemId: 'a', amount: 10, daysAgo: 5 + i * 10, now: now),
        // Ancient history, before any of this mattered.
        for (var i = 0; i < 20; i++)
          _log(itemId: 'a', amount: 999, daysAgo: 200 + i, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 1000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.single.usedInWindow, 60);
    });

    test('a future-dated log is ignored rather than trusted', () {
      // A phone with a bad clock can write tomorrow's date. It must not make the
      // rate negative or inflate the window.
      final logs = [
        for (var i = 0; i < 6; i++)
          _log(itemId: 'a', amount: 10, daysAgo: 5 + i * 10, now: now),
        _log(itemId: 'a', amount: 5000, daysAgo: -10, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 1000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.single.usedInWindow, 60);
    });
  });

  group('the figure describes the shelf', () {
    test('days remaining is stock divided by the measured rate', () {
      // 600 used across a span of 61 days (oldest log is 61 days back), so the
      // rate is 600/61 = 9.84/day and 500 left is 50.8 days. The denominator is
      // the span the logs actually cover, not the nominal window — writing this
      // test as "600 over 60 days = 50 days left" was wrong, because nothing
      // records a log at day 60.
      final logs = [
        for (var i = 0; i < 12; i++)
          _log(itemId: 'a', amount: 50, daysAgo: 61 - i * 5, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 500)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      final f = board.items.single;
      expect(f.usedInWindow, 600);
      expect(f.perDay, closeTo(600 / 61, .0001));
      expect(f.daysLeft, closeTo(500 / (600 / 61), .001));
      expect(f.daysLeft, closeTo(50.83, .01));
      expect(runwayCaption(f), contains('51 days left'));
    });

    test('an empty shelf has zero days left, not null', () {
      final logs = [
        for (var i = 0; i < 6; i++)
          _log(itemId: 'a', amount: 50, daysAgo: 5 + i * 10, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 0)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.single.daysLeft, 0);
      expect(board.items.single.soon, isTrue);
      expect(runwayCaption(board.items.single), 'empty now');
    });

    test('soonest first, so the list is a work queue', () {
      // Both hold 1000. "fast" burns 40 a day, "slow" one a day.
      final logs = [
        for (var i = 0; i < 6; i++) ...[
          _log(itemId: 'slow', amount: 1, daysAgo: 5 + i * 10, now: now),
          _log(itemId: 'fast', amount: 40, daysAgo: 5 + i * 10, now: now),
        ],
      ];
      final board = buildForecastBoard(
        chemicals: [
          _chemical(id: 'slow', name: 'Slow', quantity: 1000),
          _chemical(id: 'fast', name: 'Fast', quantity: 1000),
        ],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.map((f) => f.id), ['fast', 'slow']);
      expect(
        board.items.first.daysLeft,
        lessThan(board.items.last.daysLeft!),
      );
    });

    test('runningOut holds the month horizon', () {
      // The logs span 55 days, so "fast" runs at 240/55 = 4.36 a day. Holding
      // 100 that is 22.9 days — inside the horizon. Holding 150 it would be
      // 34 days, which is outside it; the first draft of this test used 1000
      // and asserted a 25-day figure, which was simply wrong arithmetic.
      final logs = [
        for (var i = 0; i < 6; i++) ...[
          _log(itemId: 'slow', amount: 1, daysAgo: 5 + i * 10, now: now),
          _log(itemId: 'fast', amount: 40, daysAgo: 5 + i * 10, now: now),
        ],
      ];
      ForecastBoard boardFor(double fastQuantity) => buildForecastBoard(
        chemicals: [
          _chemical(id: 'slow', name: 'Slow', quantity: 1000),
          _chemical(id: 'fast', name: 'Fast', quantity: fastQuantity),
        ],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(boardFor(100).runningOut.map((f) => f.id), ['fast']);
      // Just outside the horizon: present on the board, absent from the alarm.
      final outside = boardFor(150);
      expect(outside.items.map((f) => f.id), contains('fast'));
      expect(outside.runningOut, isEmpty);
    });

    test('an item nobody has ever used is left off the board', () {
      // Not "infinite supply" — simply unmeasured, and saying so with a date
      // would be inventing a fact.
      final logs = [
        for (var i = 0; i < 6; i++)
          _log(itemId: 'a', amount: 50, daysAgo: 5 + i * 10, now: now),
        for (var i = 0; i < 6; i++)
          _log(
            itemId: 'restocked-only',
            amount: 500,
            daysAgo: 4 + i * 10,
            now: now,
            action: InventoryAction.restock,
          ),
      ];
      final board = buildForecastBoard(
        chemicals: [
          _chemical(id: 'a', quantity: 100),
          _chemical(id: 'restocked-only', name: 'Untouched', quantity: 900),
        ],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.map((f) => f.id), ['a']);
    });
  });

  group('confidence is stated, not implied', () {
    test('steady usage over a long window is steady', () {
      final logs = [
        for (var i = 0; i < 24; i++)
          _log(itemId: 'a', amount: 10, daysAgo: 4 + i * 3, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 1000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.single.confidence, ForecastConfidence.steady);
      expect(runwayCaption(board.items.single), startsWith('lasting'));
    });

    test('a session booked across several days is still called rough', () {
      // This is the case the mean missed. 180 a day for five days does not look
      // unusual next to a mean that has been dragged up by those same five days,
      // so the first version of this rule called it steady. The median day is
      // still 10, which is the honest description.
      final logs = [
        for (var i = 0; i < 10; i++)
          _log(itemId: 'a', amount: 10, daysAgo: 5 + i * 7, now: now),
        for (var i = 0; i < 5; i++)
          _log(itemId: 'a', amount: 180, daysAgo: 30 + i, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 5000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(board.items.single.confidence, ForecastConfidence.rough);
      expect(runwayCaption(board.items.single), startsWith('roughly'));
    });

    test('a year of stock is described, not counted', () {
      final logs = [
        for (var i = 0; i < 6; i++)
          _log(itemId: 'a', amount: 1, daysAgo: 5 + i * 10, now: now),
      ];
      final board = buildForecastBoard(
        chemicals: [_chemical(id: 'a', quantity: 90000)],
        apparatus: const [],
        logs: logs,
        now: now,
      );

      expect(runwayCaption(board.items.single), 'more than a year of stock');
    });
  });

  test('an empty log set is quiet, and never divides by zero', () {
    final board = buildForecastBoard(
      chemicals: [_chemical(id: 'a', quantity: 100)],
      apparatus: const [],
      logs: const [],
      now: now,
    );

    expect(board.items, isEmpty);
    expect(board.historyDays, 0);
    expect(board.hasEnoughHistory, isFalse);
  });
}
