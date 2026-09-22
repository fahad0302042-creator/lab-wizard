import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/home/presentation/dashboard_screen.dart';
import 'package:lab_wizard/features/home/presentation/home_shell.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/notifications/notification_providers.dart';
import 'package:lab_wizard/features/reports/presentation/reports_screen.dart';
import 'package:lab_wizard/features/sync/background/background_sync.dart';
import 'package:lab_wizard/features/sync/background/background_sync_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'support/fixtures.dart';

/// TEST-02: inactive tabs of the home shell stay mounted (their state
/// survives) but are offstage: they do not paint, cannot be hit, are not in
/// the semantics tree and their tickers are muted.
class _QuietGateway implements NotificationGateway {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> areEnabled() async => false;
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required AlertChannel channel,
    String? payload,
  }) async {}
  @override
  Future<void> schedule(PlannedReminder reminder) async {}
  @override
  Future<void> cancelPending() async {}
  @override
  Future<Set<int>> pendingIds() async => const {};
  @override
  Future<void> openSettings() async {}
  @override
  Stream<String> get taps => const Stream.empty();
}

class _QuietScheduler implements BackgroundScheduler {
  @override
  Future<void> ensurePeriodic(BackgroundSyncPreferences preferences) async {}
  @override
  Future<void> scheduleFlush(BackgroundSyncPreferences preferences) async {}
  @override
  Future<void> cancelAll() async {}
}

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(() => SeededInventory(richState())),
        isOnlineProvider.overrideWithValue(() async => true),
        notificationGatewayProvider.overrideWithValue(_QuietGateway()),
        backgroundSchedulerProvider.overrideWithValue(_QuietScheduler()),
        connectivityChangesProvider.overrideWithValue(
          () => const Stream.empty(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: HomeShell(user: User.fromJson(userJson)!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Inactive pages are offstage, so finders must be told not to skip them.
Finder _all<T extends Widget>() => find.byType(T, skipOffstage: false);

RenderRepaintBoundary _page(WidgetTester tester, int index) =>
    tester.renderObject<RenderRepaintBoundary>(
      find.byKey(ValueKey('main-page-$index'), skipOffstage: false),
    );

bool _ticking(WidgetTester tester, Finder finder) =>
    TickerMode.valuesOf(tester.element(finder)).enabled;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('only the active tab paints, hits and speaks', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpShell(tester);

    // All five pages are mounted (state is kept across tab switches) but
    // only the dashboard is on stage: default finders skip the others.
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(InventoryScreen), findsNothing);
    expect(_all<InventoryScreen>(), findsNWidgets(2));
    expect(_all<ReportsScreen>(), findsOneWidget);

    // Only the dashboard has ever painted.
    expect(_page(tester, 0).debugLayer, isNotNull, reason: 'dashboard painted');
    for (final index in [1, 2, 3, 4]) {
      expect(_page(tester, index).debugLayer, isNull, reason: 'page $index');
    }

    // Inactive pages cannot be hit and are not exposed to TalkBack.
    expect(find.byType(DashboardScreen).hitTestable(), findsOneWidget);
    expect(_all<InventoryScreen>().hitTestable(), findsNothing);
    expect(_all<ReportsScreen>().hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('chemicals shelf'), findsNothing);

    // Their tickers are muted.
    expect(_ticking(tester, _all<InventoryScreen>().first), isFalse);
    expect(_ticking(tester, find.byType(DashboardScreen)), isTrue);

    // Switching tabs flips all of the above.
    await tester.tap(find.text('chems'));
    await tester.pumpAndSettle();
    expect(_page(tester, 1).debugLayer, isNotNull);
    expect(_page(tester, 3).debugLayer, isNull, reason: 'gear still unpainted');
    expect(find.byType(DashboardScreen), findsNothing, reason: 'offstage now');
    expect(_all<DashboardScreen>().hitTestable(), findsNothing);
    expect(find.byType(InventoryScreen).hitTestable(), findsOneWidget);
    expect(find.bySemanticsLabel('chemicals shelf'), findsOneWidget);
    expect(_ticking(tester, _all<DashboardScreen>()), isFalse);
    expect(_ticking(tester, find.byType(InventoryScreen)), isTrue);
    handle.dispose();
  });
}
