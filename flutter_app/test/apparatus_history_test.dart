import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/apparatus_history.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/apparatus_history_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;
}

final _item = Apparatus(
  id: 'a1',
  name: 'Centrifuge',
  category: 'equipment',
  quantity: 3,
  initialQuantity: 4,
  lowStockThreshold: 1,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  serialNumber: 'CF-42',
  condition: 'good',
);

ConsumptionLog _log(
  String id,
  InventoryAction action,
  DateTime at, {
  String itemId = 'a1',
  String note = '',
}) => ConsumptionLog(
  id: id,
  itemId: itemId,
  itemType: ItemKind.apparatus,
  action: action,
  amount: 1,
  note: note,
  loggedAt: at,
  createdAt: at,
);

InventoryState _seed() => InventoryState(
  apparatus: [_item],
  logs: [
    _log('l1', InventoryAction.breakage, DateTime(2026, 9, 10, 9), note: 'lid'),
    _log('l2', InventoryAction.restock, DateTime(2026, 9, 1, 9)),
    _log('other', InventoryAction.consume, DateTime(2026, 9, 12), itemId: 'zz'),
  ],
  reversals: [
    InventoryReversal(
      id: 'r1',
      itemId: 'a1',
      itemType: ItemKind.apparatus,
      action: InventoryAction.consume,
      amount: 1,
      reversedAt: DateTime(2026, 9, 11, 8),
    ),
  ],
  checkouts: [
    ApparatusCheckout(
      id: 'c1',
      apparatusId: 'a1',
      quantity: 2,
      returnedQuantity: 2,
      person: 'Aisha',
      checkedOutAt: DateTime(2026, 9, 2, 10),
      dueAt: DateTime(2026, 9, 5, 23, 59),
      returnedAt: DateTime(2026, 9, 7, 15),
      returnNote: 'rotor scratched',
    ),
    ApparatusCheckout(
      id: 'c2',
      apparatusId: 'a1',
      quantity: 1,
      person: 'Bilal',
      checkedOutAt: DateTime(2026, 9, 15, 11),
    ),
  ],
  services: [
    ApparatusService(
      id: 's1',
      apparatusId: 'a1',
      kind: ServiceKind.calibration,
      title: 'Speed check',
      createdAt: DateTime(2026, 8, 20, 9),
      dueAt: DateTime(2026, 9, 3, 23, 59),
      completedAt: DateTime(2026, 9, 4, 12),
      performedBy: 'Sara',
      result: 'pass',
    ),
    ApparatusService(
      id: 's2',
      apparatusId: 'a1',
      kind: ServiceKind.maintenance,
      createdAt: DateTime(2026, 9, 4, 12, 1),
      dueAt: DateTime(2026, 12, 4, 23, 59),
    ),
  ],
);

void main() {
  group('GEAR-04 timeline', () {
    test('merges stock, undo, loans and service events newest first', () {
      final state = _seed();
      final events = buildApparatusHistory(
        apparatusId: 'a1',
        logs: state.logs,
        reversals: state.reversals,
        checkouts: state.checkouts,
        services: state.services,
      );
      expect(events.map((e) => e.key), [
        'checkout-c2',
        'undo-r1',
        'breakage-l1',
        'returned-c1',
        'scheduled-s2',
        'completed-s1',
        'checkout-c1',
        'restock-l2',
        'scheduled-s1',
      ]);
      final returned = events.firstWhere((e) => e.key == 'returned-c1');
      expect(returned.title, 'Returned 2 pcs from Aisha');
      expect(returned.detail, 'late · rotor scratched');
      final completed = events.firstWhere((e) => e.key == 'completed-s1');
      expect(completed.title, 'Speed check done · pass');
      expect(completed.detail, 'calibration · by Sara · late');
      expect(
        events.firstWhere((e) => e.key == 'checkout-c1').detail,
        'due ${DateFormat('d MMM yyyy').format(DateTime(2026, 9, 5))}',
      );
      expect(
        events.firstWhere((e) => e.key == 'undo-r1').title,
        'Undid used 1 pcs',
      );
      expect(events.firstWhere((e) => e.key == 'breakage-l1').detail, 'lid');
      expect(events.where((e) => e.sourceId == 'other'), isEmpty);
    });

    test('summary and report describe the item', () {
      final state = _seed();
      final events = buildApparatusHistory(
        apparatusId: 'a1',
        logs: state.logs,
        reversals: state.reversals,
        checkouts: state.checkouts,
        services: state.services,
      );
      final summary = ApparatusHistorySummary.of(
        events,
        checkouts: state.checkouts,
        services: state.services,
        apparatusId: 'a1',
      );
      expect(summary.events, 9);
      expect(summary.damaged, 1);
      expect(summary.loans, 2);
      expect(summary.openLoans, 1);
      expect(summary.lateReturns, 1);
      expect(summary.completedTasks, 1);
      expect(summary.openTasks, 1);
      expect(summary.lastCalibration, DateTime(2026, 9, 4, 12));
      expect(summary.lastMaintenance, isNull);
      expect(summary.nextDue, DateTime(2026, 12, 4, 23, 59));

      final report = buildApparatusHistoryReport(
        item: _item,
        events: events,
        summary: summary,
        now: DateTime(2026, 9, 21, 8, 30),
      );
      expect(report, contains('Item: Centrifuge'));
      expect(report, contains('Serial: CF-42'));
      expect(report, contains('Generated: 2026-09-21 08:30'));
      expect(report, contains('- loans: 2 (1 open, 1 returned late)'));
      expect(report, contains('- last calibration: 2026-09-04'));
      expect(report, contains('- next due: 2026-12-04'));
      expect(
        report,
        contains(
          '- 2026-09-07 15:00 | returned | Returned 2 pcs from Aisha | late · rotor scratched',
        ),
      );
      // Plain text: a note starting with "=" stays a note, never a formula.
      final tricky = buildApparatusHistoryReport(
        item: _item,
        events: [
          ApparatusEvent(
            kind: ApparatusEventKind.consume,
            time: DateTime(2026, 9, 1),
            title: 'Used 1 pcs',
            detail: '=HYPERLINK("x")',
            sourceId: 'x',
          ),
        ],
        summary: summary,
      );
      expect(tricky, contains('| Used 1 pcs | =HYPERLINK("x")'));
    });

    test('filters group the event kinds', () {
      expect(HistoryFilter.stock.matches(ApparatusEventKind.undo), isTrue);
      expect(HistoryFilter.stock.matches(ApparatusEventKind.checkout), isFalse);
      expect(HistoryFilter.loans.matches(ApparatusEventKind.returned), isTrue);
      expect(
        HistoryFilter.service.matches(ApparatusEventKind.scheduled),
        isTrue,
      );
      expect(
        HistoryFilter.service.matches(ApparatusEventKind.breakage),
        isFalse,
      );
      expect(HistoryFilter.all.matches(ApparatusEventKind.completed), isTrue);
    });
  });

  group('GEAR-04 screens', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pumpScreen(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(() => _FakeInventory(_seed())),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('history screen shows summary, timeline and filters', (
      tester,
    ) async {
      await pumpScreen(tester, const ApparatusHistoryScreen(apparatusId: 'a1'));
      expect(find.byKey(const Key('history-summary')), findsOneWidget);
      expect(find.text('3 pcs in stock · 1 out'), findsOneWidget);
      expect(
        find.textContaining('2 loans · 1 open · 1 returned late'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'last calibration ${DateFormat('d MMM yyyy').format(DateTime(2026, 9, 4))}',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('timeline-checkout-c2')), findsOneWidget);
      expect(find.byKey(const Key('timeline-completed-s1')), findsOneWidget);
      expect(find.byKey(const Key('timeline-breakage-l1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-filter-loans')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timeline-checkout-c2')), findsOneWidget);
      expect(find.byKey(const Key('timeline-returned-c1')), findsOneWidget);
      expect(find.byKey(const Key('timeline-breakage-l1')), findsNothing);
      expect(find.byKey(const Key('timeline-completed-s1')), findsNothing);

      await tester.tap(find.byKey(const Key('history-filter-service')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timeline-scheduled-s2')), findsOneWidget);
      expect(find.byKey(const Key('timeline-checkout-c2')), findsNothing);
    });

    testWidgets('history screen copes with a missing item', (tester) async {
      await pumpScreen(
        tester,
        const ApparatusHistoryScreen(apparatusId: 'missing'),
      );
      expect(find.text('item not found'), findsOneWidget);
      final share = tester.widget<IconButton>(
        find.byKey(const Key('history-share')),
      );
      expect(share.onPressed, isNull);
    });

    testWidgets('item sheet mixes loans and tasks into history', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(formMemoryProvider);
              return Center(
                child: FilledButton(
                  onPressed: () => showItemDetailSheet(
                    context,
                    ref,
                    ItemKind.apparatus,
                    'a1',
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('history-all')));
      expect(
        find.byKey(const Key('history-event-checkout-c2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('history-event-completed-s1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('history-log-l1')), findsOneWidget);
      expect(find.byKey(const Key('history-undo-r1')), findsOneWidget);
      // Only the latest eight entries stay in the sheet.
      expect(find.byKey(const Key('history-event-scheduled-s1')), findsNothing);

      await tester.tap(find.byKey(const Key('history-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-summary')), findsOneWidget);
      expect(find.byKey(const Key('timeline-scheduled-s1')), findsOneWidget);
    });
  });
}
