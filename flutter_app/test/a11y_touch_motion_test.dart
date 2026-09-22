import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/home/presentation/dashboard_screen.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/reports/presentation/reports_screen.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'support/fixtures.dart';

/// A11Y-05: every tappable node is at least 48 × 48 dp on the main screens,
/// and nothing keeps animating when the system asks for reduced motion.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget dashboard() => Scaffold(
    body: DashboardScreen(
      user: User.fromJson(userJson)!,
      onNavigate: (_) {},
      onSettings: () {},
    ),
  );

  group('A11Y-05 touch targets', () {
    testWidgets('shelf in both densities and in selection mode', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(
        tester,
        const InventoryScreen(kind: ItemKind.chemical),
        size: const Size(420, 900),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(find.byTooltip('Show compact rows'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.longPress(find.text('Ethanol'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('dashboard, reports and sync center', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, dashboard(), size: const Size(420, 900));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await pumpScreen(
        tester,
        const Scaffold(body: ReportsScreen()),
        size: const Size(420, 900),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await pumpScreen(
        tester,
        const SyncCenterScreen(),
        state: richState().copyWith(
          outbox: [
            PendingOperation(
              id: 'op-1',
              userId: 'u1',
              type: 'add_chemical',
              payload: const {'id': 'c9', 'name': 'Acetone'},
              createdAt: fixtureNow,
              attempts: 2,
              status: PendingStatus.failed,
              lastError: 'permission denied',
              label: 'Add chemical Acetone',
            ),
          ],
        ),
        size: const Size(420, 900),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });

  group('A11Y-05 reduced motion', () {
    Future<void> pumpReduced(WidgetTester tester, Widget home) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(() => SeededInventory(richState())),
            isOnlineProvider.overrideWithValue(() async => true),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: home),
        ),
      );
      // Zero-length implicit animations finish within a frame or two.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the dashboard settles at once', (tester) async {
      await pumpReduced(tester, dashboard());
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('chemicals'), findsWidgets);
    });

    testWidgets('the shelf settles at once', (tester) async {
      await pumpReduced(tester, const InventoryScreen(kind: ItemKind.chemical));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('Ethanol'), findsOneWidget);
    });
  });
}
