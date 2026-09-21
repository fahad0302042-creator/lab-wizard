import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';
import 'package:lab_wizard/features/reports/presentation/reports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}
}

ConsumptionLog _log(
  String id,
  DateTime at, {
  InventoryAction action = InventoryAction.consume,
  double amount = 5,
  ItemKind kind = ItemKind.chemical,
}) => ConsumptionLog(
  id: id,
  itemId: kind == ItemKind.chemical ? 'c1' : 'a1',
  itemType: kind,
  action: action,
  amount: amount,
  note: '',
  loggedAt: at,
  createdAt: at,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ReportRange', () {
    final today = DateTime(2026, 9, 21, 15, 30);

    test('last-N-day ranges are inclusive local days ending today', () {
      final week = ReportRange.lastDays(7, today: today);
      expect(week.kind, ReportRangeKind.last7);
      expect(week.start, DateTime(2026, 9, 15));
      expect(week.end, DateTime(2026, 9, 21));
      expect(week.dayCount, 7);
      expect(week.contains(DateTime(2026, 9, 14, 23, 59, 59)), isFalse);
      expect(week.contains(DateTime(2026, 9, 15)), isTrue);
      expect(week.contains(DateTime(2026, 9, 21, 23, 59, 59)), isTrue);
      expect(week.contains(DateTime(2026, 9, 22)), isFalse);
      // Instants in another zone are judged by their local calendar day.
      final lateLocal = DateTime(2026, 9, 21, 23, 30);
      expect(week.contains(lateLocal.toUtc()), isTrue);
      expect(week.days.length, 7);
      expect(week.days.first, DateTime(2026, 9, 15));
      expect(week.label, 'last 7 days');
      expect(week.dates, '15 Sep – 21 Sep 2026');
      expect(week.fileStem, '2026-09-15_2026-09-21');
      expect(
        ReportRange.lastDays(30, today: today).kind,
        ReportRangeKind.last30,
      );
      expect(
        ReportRange.lastDays(30, today: today).start,
        DateTime(2026, 8, 23),
      );
      expect(ReportRange.lastDays(1, today: today).dayCount, 1);
    });

    test('previous ranges have the same length and end the day before', () {
      final week = ReportRange.lastDays(7, today: today);
      expect(week.previous.start, DateTime(2026, 9, 8));
      expect(week.previous.end, DateTime(2026, 9, 14));
      expect(week.previous.dayCount, 7);
      final month = ReportRange.month(2026, 3);
      expect(month.previous, ReportRange.month(2026, 2));
      expect(month.previous.dayCount, 28);
      expect(month.nextMonth, ReportRange.month(2026, 4));
      expect(ReportRange.month(2026, 1).previous, ReportRange.month(2025, 12));
      expect(week.nextMonth, isNull);
    });

    test('months and custom ranges', () {
      final september = ReportRange.month(2026, 9);
      expect(september.start, DateTime(2026, 9, 1));
      expect(september.end, DateTime(2026, 9, 30));
      expect(september.dayCount, 30);
      expect(september.label, 'September 2026');
      expect(september.isCurrentMonth(today: today), isTrue);
      expect(ReportRange.month(2026, 8).isCurrentMonth(today: today), isFalse);
      expect(ReportRange.month(2024, 2).dayCount, 29);

      final custom = ReportRange.custom(
        DateTime(2026, 9, 21, 18),
        DateTime(2026, 9, 3, 2),
      );
      expect(custom.kind, ReportRangeKind.custom);
      expect(custom.start, DateTime(2026, 9, 3));
      expect(custom.end, DateTime(2026, 9, 21));
      expect(custom.label, '3 – 21 Sep 2026');
      expect(
        ReportRange.custom(DateTime(2026, 8, 30), DateTime(2026, 9, 2)).label,
        '30 Aug – 2 Sep 2026',
      );
      expect(
        ReportRange.custom(DateTime(2025, 12, 30), DateTime(2026, 1, 2)).label,
        '30 Dec 2025 – 2 Jan 2026',
      );
      expect(
        ReportRange.custom(DateTime(2026, 9, 5), DateTime(2026, 9, 5)).label,
        '5 Sep 2026',
      );
      expect(
        custom,
        ReportRange.custom(DateTime(2026, 9, 3), DateTime(2026, 9, 21)),
      );
    });

    test('buckets are daily for short ranges and weekly for long ones', () {
      final month = ReportRange.month(2026, 9);
      final daily = bucketize(month, [
        DateTime(2026, 9, 1, 8),
        DateTime(2026, 9, 1, 20),
        DateTime(2026, 9, 30, 23, 59),
        DateTime(2026, 10, 1), // outside
      ]);
      expect(daily, hasLength(30));
      expect(daily.first.count, 2);
      expect(daily.first.label, '1');
      expect(daily.last.count, 1);
      expect(daily.fold(0, (sum, bucket) => sum + bucket.count), 3);

      final quarter = ReportRange.custom(
        DateTime(2026, 7, 1),
        DateTime(2026, 9, 21),
      );
      expect(quarter.dayCount, 83);
      final weekly = bucketize(quarter, [
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 7, 23),
        DateTime(2026, 7, 8),
        DateTime(2026, 9, 21, 12),
      ]);
      expect(weekly, hasLength(12));
      expect(weekly.first.start, DateTime(2026, 7, 1));
      expect(weekly.first.end, DateTime(2026, 7, 7));
      expect(weekly.first.count, 2);
      expect(weekly[1].count, 1);
      expect(weekly.last.end, DateTime(2026, 9, 21));
      expect(weekly.last.count, 1);
      expect(weekly.first.label, '1 Jul');
    });
  });

  group('reports screen', () {
    testWidgets('filters the activity by the chosen range', (tester) async {
      tester.view.physicalSize = const Size(420, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final logs = [
        _log('l1', today),
        _log('l2', DateTime(today.year, today.month, today.day - 3, 9)),
        _log('l3', DateTime(today.year, today.month, today.day - 20, 9)),
        _log('l4', DateTime(today.year, today.month, today.day - 45, 9)),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(
                InventoryState(
                  chemicals: [
                    Chemical(
                      id: 'c1',
                      name: 'Acetone',
                      formula: 'C3H6O',
                      unit: 'mL',
                      quantity: 40,
                      initialQuantity: 100,
                      lowStockThreshold: 10,
                      notes: '',
                      qrCode: 'q',
                      createdAt: DateTime(2026, 1, 1),
                    ),
                  ],
                  apparatus: [
                    Apparatus(
                      id: 'a1',
                      name: 'Beaker',
                      category: 'glassware',
                      quantity: 4,
                      initialQuantity: 6,
                      lowStockThreshold: 1,
                      notes: '',
                      createdAt: DateTime(2026, 1, 1),
                    ),
                  ],
                  checkouts: [
                    ApparatusCheckout(
                      id: 'l1',
                      apparatusId: 'a1',
                      quantity: 2,
                      person: 'Ali',
                      checkedOutAt: DateTime(
                        today.year,
                        today.month,
                        today.day - 10,
                      ),
                      dueAt: DateTime(today.year, today.month, today.day - 3),
                    ),
                  ],
                  services: [
                    ApparatusService(
                      id: 's1',
                      apparatusId: 'a1',
                      kind: ServiceKind.calibration,
                      createdAt: DateTime(2026, 1, 1),
                      dueAt: DateTime(today.year, today.month, today.day - 5),
                    ),
                  ],
                  logs: [
                    ...logs,
                    ConsumptionLog(
                      id: 'b1',
                      itemId: 'a1',
                      itemType: ItemKind.apparatus,
                      action: InventoryAction.breakage,
                      amount: 2,
                      note: '',
                      loggedAt: today,
                      createdAt: today,
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('report'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-range-last7')));
      await tester.pumpAndSettle();
      expect(find.text('last 7 days'), findsOneWidget);
      expect(find.byTooltip('Previous month'), findsNothing);
      expect(find.text('consume'), findsNWidgets(2));
      // REPORT-02: quantities per unit and the change against the week before.
      final usage = find.byKey(const Key('metric-consume'));
      expect(
        find.descendant(of: usage, matching: find.text('10 mL')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: usage, matching: find.text('none before')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('trend-note')), findsOneWidget);
      // REPORT-03: four uses over 46 days of history give an estimate with
      // its reasoning; the range above does not change it.
      expect(find.byKey(const Key('runout-c1')), findsOneWidget);
      expect(
        find.textContaining('4 uses totalling 20 mL over the last 46 days'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('runout-gaps')), findsNothing);

      await tester.tap(find.byKey(const Key('report-range-last30')));
      await tester.pumpAndSettle();
      expect(find.text('last 30 days'), findsOneWidget);
      expect(find.text('consume'), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byKey(const Key('metric-consume')),
          matching: find.text('+200% vs before'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('report-range-month')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Previous month'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);

      // REPORT-04: chemical shelf shows expiry + damage; apparatus shelf shows
      // damage, overdue loans and due services.
      expect(find.byKey(const Key('report-expiry')), findsOneWidget);
      expect(find.byKey(const Key('report-damage')), findsOneWidget);
      expect(find.byKey(const Key('report-loans')), findsNothing);
      expect(find.text('No damage recorded in this range.'), findsOneWidget);
      await tester.tap(find.text('apparatus'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-expiry')), findsNothing);
      expect(find.byKey(const Key('damage-a1')), findsOneWidget);
      expect(find.byKey(const Key('loan-l1')), findsOneWidget);
      expect(find.text('3 days overdue'), findsOneWidget);
      expect(find.byKey(const Key('service-s1')), findsOneWidget);
      expect(find.text('overdue by 5 days'), findsOneWidget);
      await tester.tap(find.text('chemicals'));
      await tester.pumpAndSettle();
      // REPORT-05: spreadsheet exports sit next to the PDF button.
      expect(find.byKey(const Key('export-activity-csv')), findsOneWidget);
      expect(find.byKey(const Key('export-inventory-csv')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-range-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Report range (inclusive)'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Previous month'), findsOneWidget);
    });
  });
}
