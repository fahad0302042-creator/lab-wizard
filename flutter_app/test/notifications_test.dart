import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/notifications/notification_providers.dart';
import 'package:lab_wizard/features/notifications/presentation/alerts_screen.dart';
import 'package:lab_wizard/features/notifications/presentation/notification_settings_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;
}

/// Monday 21 Sep 2026, 10:00 local.
final _now = DateTime(2026, 9, 21, 10);

Chemical _chem(
  String id,
  String name, {
  double quantity = 50,
  double threshold = 5,
  DateTime? expiry,
}) => Chemical(
  id: id,
  name: name,
  formula: '',
  unit: 'g',
  quantity: quantity,
  initialQuantity: 100,
  lowStockThreshold: threshold,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  expiryDate: expiry,
);

Apparatus _gear(String id, String name, {double quantity = 4}) => Apparatus(
  id: id,
  name: name,
  category: 'glassware',
  quantity: quantity,
  initialQuantity: quantity,
  lowStockThreshold: 1,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
);

final _seed = InventoryState(
  chemicals: [
    _chem('acid', 'Acetic acid', quantity: 2),
    _chem('salt', 'Sodium chloride', quantity: 0),
    _chem('ether', 'Diethyl ether', expiry: DateTime(2026, 9, 25)),
    _chem('old', 'Old reagent', expiry: DateTime(2026, 9, 1)),
    _chem('fine', 'Fine reagent', expiry: DateTime(2027, 3, 1)),
  ],
  apparatus: [_gear('beaker', 'Beaker'), _gear('balance', 'Balance')],
  checkouts: [
    ApparatusCheckout(
      id: 'l1',
      apparatusId: 'beaker',
      quantity: 2,
      person: 'Aisha',
      checkedOutAt: DateTime(2026, 9, 10),
      dueAt: DateTime(2026, 9, 19, 23, 59),
    ),
    ApparatusCheckout(
      id: 'l2',
      apparatusId: 'balance',
      quantity: 1,
      person: 'Bilal',
      checkedOutAt: DateTime(2026, 9, 20),
      dueAt: DateTime(2026, 9, 30, 23, 59),
    ),
    ApparatusCheckout(
      id: 'l3',
      apparatusId: 'beaker',
      quantity: 1,
      checkedOutAt: DateTime(2026, 9, 1),
      dueAt: DateTime(2026, 9, 2, 23, 59),
      returnedQuantity: 1,
      returnedAt: DateTime(2026, 9, 2),
    ),
  ],
  services: [
    ApparatusService(
      id: 's1',
      apparatusId: 'balance',
      kind: ServiceKind.calibration,
      createdAt: DateTime(2026, 8, 1),
      dueAt: DateTime(2026, 9, 10),
    ),
    ApparatusService(
      id: 's2',
      apparatusId: 'balance',
      kind: ServiceKind.maintenance,
      createdAt: DateTime(2026, 8, 1),
      dueAt: DateTime(2026, 9, 28),
    ),
    ApparatusService(
      id: 's3',
      apparatusId: 'beaker',
      kind: ServiceKind.maintenance,
      createdAt: DateTime(2026, 8, 1),
      dueAt: DateTime(2026, 9, 15),
      completedAt: DateTime(2026, 9, 14),
    ),
  ],
  outbox: [
    PendingOperation(
      id: 'op1',
      userId: 'u1',
      type: 'update_item',
      payload: const {},
      createdAt: DateTime(2026, 9, 20),
      status: PendingStatus.failed,
      label: 'Restock Beaker',
      lastError: 'boom',
    ),
  ],
  logs: [
    ConsumptionLog(
      id: 'log1',
      itemId: 'acid',
      itemType: ItemKind.chemical,
      action: InventoryAction.consume,
      amount: 5,
      note: '',
      loggedAt: DateTime(2026, 9, 20),
      createdAt: DateTime(2026, 9, 20),
    ),
    ConsumptionLog(
      id: 'log2',
      itemId: 'acid',
      itemType: ItemKind.chemical,
      action: InventoryAction.restock,
      amount: 5,
      note: '',
      loggedAt: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
    ),
  ],
);

const _allOn = NotificationPreferences(enabled: true, weeklySummary: true);

List<AppAlert> _alerts([NotificationPreferences preferences = _allOn]) =>
    buildAlerts(
      preferences: preferences,
      chemicals: _seed.chemicals,
      apparatus: _seed.apparatus,
      checkouts: _seed.checkouts,
      services: _seed.services,
      outbox: _seed.outbox,
      now: _now,
    );

void main() {
  group('preferences (NOTIFY-01)', () {
    test('defaults are quiet and survive an encode/decode round trip', () {
      const defaults = NotificationPreferences();
      expect(defaults.enabled, isFalse);
      expect(defaults.lowStock, isTrue);
      expect(defaults.weeklySummary, isFalse);
      final changed = defaults.copyWith(
        enabled: true,
        expiryDays: 60,
        serviceDays: 7,
        summaryWeekday: DateTime.friday,
        summaryHour: 17,
        reminderHour: 8,
        weeklySummary: true,
      );
      final restored = NotificationPreferences.decode(changed.encode());
      expect(restored.toMap(), changed.toMap());
    });

    test('bad or missing values fall back to defaults', () {
      expect(
        NotificationPreferences.decode(null).toMap(),
        const NotificationPreferences().toMap(),
      );
      expect(
        NotificationPreferences.decode('{not json').toMap(),
        const NotificationPreferences().toMap(),
      );
      final odd = NotificationPreferences.fromMap({
        'enabled': 'yes',
        'expiry_days': -4,
        'summary_weekday': 9,
        'reminder_hour': 25,
        'service_days': 3,
      });
      expect(odd.enabled, isFalse);
      expect(odd.expiryDays, 30);
      expect(odd.summaryWeekday, DateTime.monday);
      expect(odd.reminderHour, 9);
      expect(odd.serviceDays, 3);
    });

    test('dropdown option lists always contain the saved value', () {
      expect(withValue(const [7, 14, 30], 14), [7, 14, 30]);
      expect(withValue(const [7, 14, 30], 10), [7, 10, 14, 30]);
    });
  });

  group('alerts (NOTIFY-02/03/04)', () {
    test('covers stock, expiry, returns, service and sync, urgent first', () {
      final alerts = _alerts();
      final ids = alerts.map((alert) => alert.id).toList();
      expect(
        ids,
        containsAll([
          'empty:salt',
          'low:acid',
          'expired:old',
          'expiring:ether',
          'overdueReturn:l1',
          'serviceOverdue:s1',
          'serviceDue:s2',
          'syncFailed',
        ]),
      );
      expect(ids, isNot(contains('expiring:fine')));
      expect(ids, isNot(contains('overdueReturn:l2')));
      expect(ids, isNot(contains('overdueReturn:l3')));
      expect(ids, isNot(contains('serviceDue:s3')));
      final kinds = alerts.map((alert) => alert.kind.index).toList();
      expect(kinds, List.of(kinds)..sort());
      expect(alerts.first.kind, AlertKind.empty);
      expect(alerts.where((alert) => alert.kind.urgent).length, 5);
    });

    test('bodies and payloads point at the right place', () {
      final byId = {for (final alert in _alerts()) alert.id: alert};
      expect(byId['low:acid']!.body, '2 g left · warning level 5 g');
      expect(byId['low:acid']!.payload, 'chemical:acid');
      expect(byId['expired:old']!.body, contains('20 days ago'));
      expect(byId['expiring:ether']!.title, 'Diethyl ether expires in 4 days');
      expect(byId['overdueReturn:l1']!.title, 'Beaker not back from Aisha');
      expect(byId['overdueReturn:l1']!.body, '2 pcs · overdue by 2 days');
      expect(byId['overdueReturn:l1']!.payload, 'apparatus:beaker');
      expect(byId['serviceOverdue:s1']!.title, 'Balance · calibration overdue');
      expect(byId['serviceDue:s2']!.title, 'Balance · maintenance in 7 days');
      expect(byId['syncFailed']!.title, '1 change could not be saved');
      expect(byId['syncFailed']!.body, contains('Restock Beaker'));
      expect(byId['syncFailed']!.payload, 'sync');
    });

    test('per-kind switches remove their alerts', () {
      final quiet = _alerts(
        const NotificationPreferences(
          lowStock: false,
          expiry: false,
          returns: false,
          service: false,
          syncProblems: false,
        ),
      );
      expect(quiet, isEmpty);
      final onlyExpiry = _alerts(
        const NotificationPreferences(
          lowStock: false,
          returns: false,
          service: false,
          syncProblems: false,
          expiryDays: 3,
        ),
      );
      expect(onlyExpiry.map((alert) => alert.id), ['expired:old']);
    });

    test('weekly summary text counts the week', () {
      final text = weeklySummaryText(
        alerts: _alerts(),
        logs: _seed.logs,
        chemicalCount: 5,
        apparatusCount: 2,
        now: _now,
      );
      expect(text, contains('5 chemicals and 2 apparatus'));
      expect(text, contains('1 uses, 0 restocks, 0 damage'));
      expect(text, contains('1 out of stock, 1 running low.'));
      expect(text, contains('1 expired, 1 expiring soon.'));
      expect(text, contains('1 overdue return.'));
      expect(text, contains('1 service tasks overdue, 1 due soon.'));
    });
  });

  group('planned reminders', () {
    test('ids are stable, positive and distinct', () {
      expect(notificationIdFor('return:l1'), notificationIdFor('return:l1'));
      expect(notificationIdFor('return:l1'), greaterThan(0));
      expect(
        notificationIdFor('return:l1'),
        isNot(notificationIdFor('return:l2')),
      );
    });

    test('only future times are planned, soonest first, weekly last', () {
      final plan = planReminders(
        preferences: _allOn,
        chemicals: _seed.chemicals,
        apparatus: _seed.apparatus,
        checkouts: _seed.checkouts,
        services: _seed.services,
        now: _now,
      );
      final keys = plan.map((reminder) => reminder.key).toList();
      expect(keys, [
        'expiry-day:ether',
        'service-due:s2',
        'return:l2',
        'expiry-soon:fine',
        'expiry-day:fine',
        'weekly-summary',
      ]);
      expect(plan[0].at, DateTime(2026, 9, 25, 9));
      expect(plan[1].at, DateTime(2026, 9, 28, 9));
      expect(plan[2].at, DateTime(2026, 9, 30, 23, 59));
      expect(plan[2].title, 'Balance is due back from Bilal');
      expect(plan[2].payload, 'apparatus:balance');
      expect(plan[3].at, DateTime(2027, 1, 30, 9));
      expect(plan.last.weekly, isTrue);
      expect(plan.last.at, DateTime(2026, 9, 28, 9));
      expect(plan.last.channel, AlertChannel.summary);
    });

    test('respects the master switch, the kind switches and the cap', () {
      expect(
        planReminders(
          preferences: const NotificationPreferences(),
          chemicals: _seed.chemicals,
          now: _now,
        ),
        isEmpty,
      );
      final noExpiry = planReminders(
        preferences: _allOn.copyWith(expiry: false, weeklySummary: false),
        chemicals: _seed.chemicals,
        apparatus: _seed.apparatus,
        checkouts: _seed.checkouts,
        services: _seed.services,
        now: _now,
      );
      expect(noExpiry.map((r) => r.key), ['service-due:s2', 'return:l2']);
      final capped = planReminders(
        preferences: _allOn,
        chemicals: _seed.chemicals,
        apparatus: _seed.apparatus,
        checkouts: _seed.checkouts,
        services: _seed.services,
        now: _now,
        limit: 2,
      );
      expect(capped.map((r) => r.key), [
        'expiry-day:ether',
        'service-due:s2',
        'weekly-summary',
      ]);
    });

    test('next weekly slot skips today once the hour has passed', () {
      expect(
        nextWeeklySlot(weekday: DateTime.monday, hour: 9, now: _now),
        DateTime(2026, 9, 28, 9),
      );
      expect(
        nextWeeklySlot(weekday: DateTime.monday, hour: 12, now: _now),
        DateTime(2026, 9, 21, 12),
      );
      expect(
        nextWeeklySlot(weekday: DateTime.sunday, hour: 18, now: _now),
        DateTime(2026, 9, 27, 18),
      );
    });
  });

  group('coordinator', () {
    late RecordingNotificationGateway gateway;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      gateway = RecordingNotificationGateway();
      container = ProviderContainer(
        overrides: [
          inventoryProvider.overrideWith(() => _FakeInventory(_seed)),
          notificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
    });

    test('does nothing while the master switch is off', () async {
      final coordinator = container.read(
        notificationCoordinatorProvider.notifier,
      );
      await coordinator.dispatch(force: true);
      expect(gateway.initializeCalls, 0);
      expect(gateway.shown, isEmpty);
      expect(gateway.scheduled, isEmpty);
    });

    test('shows a digest once per day and re-plans reminders', () async {
      final coordinator = container.read(
        notificationCoordinatorProvider.notifier,
      );
      coordinator.now = () => _now;
      await container
          .read(notificationPreferencesProvider.notifier)
          .update((current) => _allOn);
      await coordinator.dispatch(force: true);

      expect(gateway.shown, hasLength(1));
      expect(gateway.shown.single.title, '8 things need attention');
      expect(gateway.shown.single.body, contains('5 urgent'));
      expect(gateway.shown.single.payload, 'alerts');
      expect(
        gateway.scheduled.map((reminder) => reminder.key),
        contains('weekly-summary'),
      );
      final status = container.read(notificationCoordinatorProvider);
      expect(status.scheduledCount, gateway.scheduled.length);
      expect(status.shownCount, 8);
      expect(status.lastError, isNull);

      gateway.shown.clear();
      await coordinator.dispatch();
      expect(gateway.shown, isEmpty, reason: 'same day, nothing new');

      coordinator.now = () => _now.add(const Duration(days: 1));
      await coordinator.dispatch();
      expect(gateway.shown, hasLength(1), reason: 'a new day repeats once');
    });

    test('few new alerts are shown individually with item payloads', () async {
      SharedPreferences.setMockInitialValues({});
      final small = ProviderContainer(
        overrides: [
          inventoryProvider.overrideWith(
            () => _FakeInventory(
              InventoryState(chemicals: [_chem('acid', 'Acid', quantity: 1)]),
            ),
          ),
          notificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(small.dispose);
      final coordinator = small.read(notificationCoordinatorProvider.notifier);
      coordinator.now = () => _now;
      await small
          .read(notificationPreferencesProvider.notifier)
          .update((current) => _allOn);
      await coordinator.dispatch(force: true);
      expect(gateway.shown, hasLength(1));
      expect(gateway.shown.single.title, 'Acid is running low');
      expect(gateway.shown.single.payload, 'chemical:acid');
      expect(gateway.shown.single.id, notificationIdFor('low:acid'));
    });

    test('a denied permission keeps the master switch off', () async {
      gateway.permission = false;
      final coordinator = container.read(
        notificationCoordinatorProvider.notifier,
      );
      expect(await coordinator.enable(), isFalse);
      expect(container.read(notificationPreferencesProvider).enabled, isFalse);
      expect(container.read(notificationCoordinatorProvider).blocked, isTrue);
      expect(gateway.permissionRequests, 1);
    });

    test('gateway failures surface as a message, not a crash', () async {
      gateway.failWith = StateError('no notifications here');
      final coordinator = container.read(
        notificationCoordinatorProvider.notifier,
      );
      await container
          .read(notificationPreferencesProvider.notifier)
          .update((current) => _allOn);
      await coordinator.dispatch(force: true);
      expect(
        container.read(notificationCoordinatorProvider).lastError,
        'no notifications here',
      );
    });
  });

  group('widgets', () {
    Future<RecordingNotificationGateway> pump(
      WidgetTester tester,
      Widget child, {
      bool permission = true,
      InventoryState? seed,
    }) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = RecordingNotificationGateway(permission: permission);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(() => _FakeInventory(seed ?? _seed)),
            notificationGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: child),
        ),
      );
      await tester.pumpAndSettle();
      return gateway;
    }

    testWidgets('settings card turns notifications on and sends a test', (
      tester,
    ) async {
      final gateway = await pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: NotificationSettingsCard()),
        ),
      );
      expect(find.text('Off · the alerts list in the app still works'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('notify-test'))).enabled,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('notify-master')));
      await tester.pumpAndSettle();
      expect(gateway.permissionRequests, 1);
      expect(find.text('On · reminders at 09:00'), findsOneWidget);
      expect(gateway.shown, hasLength(1), reason: 'digest for the seed data');

      await tester.ensureVisible(find.byKey(const Key('notify-test')));
      await tester.tap(find.byKey(const Key('notify-test')));
      await tester.pumpAndSettle();
      expect(gateway.shown.last.title, 'Lab Wizard notifications work');

      await tester.ensureVisible(find.byKey(const Key('notify-weekly')));
      await tester.tap(find.byKey(const Key('notify-weekly')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notify-weekly-day')), findsOneWidget);

      // Let the debounced re-plan run so no timer outlives the test.
      await tester.pump(NotificationCoordinator.debounce * 2);
      await tester.pumpAndSettle();
      expect(
        gateway.scheduled.map((reminder) => reminder.key),
        contains('weekly-summary'),
      );
      final store = await SharedPreferences.getInstance();
      expect(
        NotificationPreferences.decode(
          store.getString(NotificationPreferencesController.storageKey),
        ).weeklySummary,
        isTrue,
      );
    });

    testWidgets('settings card explains a blocked permission', (tester) async {
      final gateway = await pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: NotificationSettingsCard()),
        ),
        permission: false,
      );
      await tester.tap(find.byKey(const Key('notify-master')));
      await tester.pumpAndSettle();
      expect(find.text('Blocked in the system settings'), findsOneWidget);
      expect(find.byKey(const Key('notify-open-settings')), findsOneWidget);
      await tester.tap(find.byKey(const Key('notify-open-settings')));
      await tester.pumpAndSettle();
      expect(gateway.settingsOpened, 1);
      expect(gateway.shown, isEmpty);
    });

    testWidgets('alerts screen lists everything and the reminders card opens it', (
      tester,
    ) async {
      await pump(tester, const Scaffold(body: RemindersCard()));
      expect(find.text('6 reminders'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminders-card')));
      await tester.pumpAndSettle();
      expect(find.text('needs attention'), findsOneWidget);
      expect(find.text('now · 5'), findsOneWidget);
      expect(find.text('coming up · 3'), findsOneWidget);
      expect(find.byKey(const Key('alert-empty:salt')), findsOneWidget);
      expect(find.text('Beaker not back from Aisha'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('weekly-summary-card')),
        200,
      );
      expect(find.textContaining('5 chemicals and 2 apparatus'), findsOneWidget);
    });

    testWidgets('reminders card hides when only stock needs attention', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(body: RemindersCard()),
        seed: InventoryState(chemicals: [_chem('acid', 'Acid', quantity: 1)]),
      );
      expect(find.byKey(const Key('reminders-card')), findsNothing);
    });
  });
}
