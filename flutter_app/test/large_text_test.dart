import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/home/presentation/dashboard_screen.dart';
import 'package:lab_wizard/features/home/presentation/home_shell.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/reports/presentation/reports_screen.dart';
import 'package:lab_wizard/features/security/app_lock_providers.dart';
import 'package:lab_wizard/features/security/presentation/lock_screen.dart';
import 'package:lab_wizard/features/sync/domain/sync_conflict.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'support/fixtures.dart';

/// A11Y-02: the main screens at Android's largest font scale (200 %) on a
/// small phone. Any RenderFlex overflow is reported as a test exception,
/// so a passing run means "nothing is clipped".
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A11Y-02 at 200 % text on a small phone', () {
    testWidgets('chemical shelf, detailed and compact', (tester) async {
      await pumpScreen(
        tester,
        const InventoryScreen(kind: ItemKind.chemical),
        scale: maxTextScale,
      );
      expect(find.text('Ethanol'), findsOneWidget);
      await tester.tap(find.byTooltip('Show compact rows'));
      await tester.pumpAndSettle();
      expect(find.text('Ethanol'), findsOneWidget);
      // Selection mode adds marks and the action bar.
      await tester.longPress(find.text('Ethanol'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsWidgets);
    });

    testWidgets('apparatus shelf with marks', (tester) async {
      await pumpScreen(
        tester,
        const InventoryScreen(kind: ItemKind.apparatus),
        scale: maxTextScale,
      );
      expect(find.textContaining('Analytical balance'), findsOneWidget);
      await tester.tap(find.byTooltip('Show compact rows'));
      await tester.pumpAndSettle();
    });

    testWidgets('item detail sheet', (tester) async {
      await pumpScreen(
        tester,
        sheetOpener(
          (context, ref) =>
              showItemDetailSheet(context, ref, ItemKind.chemical, 'c1'),
        ),
        scale: maxTextScale,
      );
      await openSheet(tester);
      expect(find.textContaining('Hydrochloric'), findsWidgets);
    });

    testWidgets('apparatus detail sheet', (tester) async {
      await pumpScreen(
        tester,
        sheetOpener(
          (context, ref) =>
              showItemDetailSheet(context, ref, ItemKind.apparatus, 'a1'),
        ),
        scale: maxTextScale,
      );
      await openSheet(tester);
      expect(find.textContaining('Analytical balance'), findsWidgets);
    });

    testWidgets('add and edit forms', (tester) async {
      await pumpScreen(
        tester,
        sheetOpener(
          (context, ref) => showAddItemSheet(context, ref, ItemKind.chemical),
        ),
        scale: maxTextScale,
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('chemical-details-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Add to shelf'), findsOneWidget);
    });

    testWidgets('edit form with every field filled', (tester) async {
      await pumpScreen(
        tester,
        sheetOpener(
          (context, ref) => showEditItemSheet(
            context,
            ref,
            kind: ItemKind.chemical,
            itemId: 'c1',
          ),
        ),
        scale: maxTextScale,
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('chemical-details-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('consume sheet', (tester) async {
      await pumpScreen(
        tester,
        sheetOpener(
          (context, ref) => showInventoryActionSheet(
            context,
            ref,
            kind: ItemKind.chemical,
            itemId: 'c1',
            action: InventoryAction.consume,
          ),
        ),
        scale: maxTextScale,
      );
      await openSheet(tester);
      expect(find.text('consume'), findsOneWidget);
    });

    testWidgets('dashboard', (tester) async {
      await pumpScreen(
        tester,
        DashboardScreen(
          user: User.fromJson(userJson)!,
          onNavigate: (_) {},
          onSettings: () {},
        ),
        scale: maxTextScale,
      );
      expect(find.textContaining('Aisha'), findsWidgets);
    });

    testWidgets('reports', (tester) async {
      await pumpScreen(tester, const ReportsScreen(), scale: maxTextScale);
      expect(find.byKey(const Key('metric-consume')), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-range-month')));
      await tester.pumpAndSettle();
    });

    testWidgets('sync center with conflicts', (tester) async {
      final state = richState().copyWith(
        outbox: [
          PendingOperation(
            id: 'op-1',
            userId: 'u1',
            type: 'inventory_action',
            payload: const {'item_id': 'c2', 'action': 'consume', 'amount': 90},
            createdAt: fixtureNow.subtract(const Duration(minutes: 6)),
            attempts: 2,
            status: PendingStatus.failed,
            lastError: 'Insufficient stock: only 80 available',
            label: 'Consume 90 mL of Ethanol',
            conflict: SyncConflict.stock(
              available: 80,
              requested: 90,
              unit: 'mL',
              partialAllowed: true,
            ),
          ),
          PendingOperation(
            id: 'op-2',
            userId: 'u1',
            type: 'add_chemical',
            payload: const {'id': 'c9', 'name': 'Acetone'},
            createdAt: fixtureNow.subtract(const Duration(minutes: 3)),
            label: 'Add chemical Acetone',
          ),
        ],
      );
      await pumpScreen(
        tester,
        const SyncCenterScreen(),
        state: state,
        scale: maxTextScale,
      );
      expect(find.text('Add chemical Acetone'), findsOneWidget);
    });

    testWidgets('lock screen keypad', (tester) async {
      await pumpScreen(
        tester,
        const LockScreen(),
        overrides: [appLockProvider.overrideWith(LockedLock.new)],
        scale: maxTextScale,
      );
      expect(find.byKey(const Key('lock-key-5')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lock-forgot')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock-forgot-confirm')), findsOneWidget);
    });

    testWidgets('bottom navigation', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: NotebookBottomNavigation(
            selectedIndex: 2,
            onSelected: (_) {},
          ),
        ),
        scale: maxTextScale,
      );
      expect(find.text('reports'), findsOneWidget);
    });
  });
}
