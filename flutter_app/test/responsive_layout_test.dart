import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/features/home/presentation/dashboard_screen.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/reports/presentation/reports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'support/fixtures.dart';

/// A11Y-03: the main screens at the widths and orientations the app
/// supports. Any overflow fails the test; a few structural checks make sure
/// wide screens actually use their space.
const _sizes = <String, Size>{
  'small phone': Size(320, 568),
  'phone landscape': Size(740, 360),
  'small tablet': Size(600, 960),
  'tablet landscape': Size(1024, 720),
};

InventoryState _longShelf() => InventoryState(
  chemicals: [
    for (var index = 0; index < 14; index++)
      chemicalFixture(
        'r$index',
        '${String.fromCharCode(65 + index)}-reagent grade solution',
        quantity: 100.0 * (index + 1),
      ),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A11Y-03 layouts', () {
    for (final entry in _sizes.entries) {
      final size = entry.value;

      testWidgets('${entry.key}: chemical shelf in both densities', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          size: size,
        );
        expect(find.text('Ethanol'), findsOneWidget);
        await tester.tap(find.byTooltip('Show compact rows'));
        await tester.pumpAndSettle();
        expect(find.text('Ethanol'), findsOneWidget);
        await tester.longPress(find.text('Ethanol'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('selection-actions')), findsOneWidget);
      });

      testWidgets('${entry.key}: long shelf with the A–Z strip', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          state: _longShelf(),
          size: size,
        );
        expect(find.byKey(const Key('alpha-A')), findsOneWidget);
        await tester.tap(find.byKey(const Key('alpha-M')));
        await tester.pumpAndSettle();
        expect(find.textContaining('M-reagent'), findsOneWidget);
      });

      testWidgets('${entry.key}: apparatus shelf', (tester) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.apparatus),
          size: size,
        );
        expect(find.textContaining('Analytical balance'), findsOneWidget);
      });

      testWidgets('${entry.key}: dashboard', (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: DashboardScreen(
              user: User.fromJson(userJson)!,
              onNavigate: (_) {},
              onSettings: () {},
            ),
          ),
          size: size,
        );
        await tester.scrollUntilVisible(
          find.text('chemicals').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('chemicals'), findsWidgets);
      });

      testWidgets('${entry.key}: reports', (tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: ReportsScreen()),
          size: size,
        );
        expect(find.byKey(const Key('metric-consume')), findsOneWidget);
      });

      testWidgets('${entry.key}: detail sheet and add form', (tester) async {
        await pumpScreen(
          tester,
          sheetOpener(
            (context, ref) =>
                showItemDetailSheet(context, ref, ItemKind.chemical, 'c1'),
          ),
          size: size,
        );
        await openSheet(tester);
        expect(find.textContaining('Hydrochloric'), findsWidgets);
        // Sheets never stretch across a tablet.
        final sheet = tester.getSize(find.byType(NotebookSheetFrame));
        expect(sheet.width, lessThanOrEqualTo(640));
      });
    }

    testWidgets('tablet landscape shows two cards per row', (tester) async {
      await pumpScreen(
        tester,
        const InventoryScreen(kind: ItemKind.chemical),
        size: _sizes['tablet landscape']!,
      );
      final ethanol = tester.getTopLeft(find.text('Ethanol')).dy;
      final acid = tester.getTopLeft(find.textContaining('Hydrochloric')).dy;
      final pellets = tester.getTopLeft(find.textContaining('Sodium')).dy;
      // Cards are drawn with a slight alternating tilt, hence the tolerance.
      expect(ethanol, closeTo(acid, 8), reason: 'first row holds two cards');
      expect(pellets, greaterThan(ethanol), reason: 'third card wraps');
      expect(shelfColumns(1024), 2);
      expect(shelfColumns(600), 1);
    });

    testWidgets('phones keep one card per row', (tester) async {
      await pumpScreen(
        tester,
        const InventoryScreen(kind: ItemKind.chemical),
        size: _sizes['small phone']!,
      );
      final ethanol = tester.getTopLeft(find.text('Ethanol')).dy;
      final acid = tester.getTopLeft(find.textContaining('Hydrochloric')).dy;
      expect((ethanol - acid).abs(), greaterThan(40));
    });

    testWidgets('the A–Z strip thins out when the list is short', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const InventoryScreen(kind: ItemKind.chemical),
        state: _longShelf(),
        size: _sizes['phone landscape']!,
      );
      // Every second letter is shown; the hidden ones are simply absent.
      expect(find.byKey(const Key('alpha-A')), findsOneWidget);
      expect(find.byKey(const Key('alpha-B')), findsNothing);
      expect(
        AlphabetIndex.lettersFor(1000),
        hasLength(alphabetIndexLetters.length),
      );
      expect(
        AlphabetIndex.lettersFor(120).length,
        lessThan(alphabetIndexLetters.length),
      );
      expect(AlphabetIndex.lettersFor(20), isEmpty);
    });

    testWidgets('tablet dashboard puts the four tiles in one row', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: DashboardScreen(
            user: User.fromJson(userJson)!,
            onNavigate: (_) {},
            onSettings: () {},
          ),
        ),
        size: _sizes['small tablet']!,
      );
      await tester.scrollUntilVisible(
        find.text('need attention').first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final tops = [
        for (final label in ['chemicals', 'apparatus', 'need attention'])
          tester.getTopLeft(find.text(label).first).dy,
      ];
      // Tiles are drawn with a slight alternating tilt, hence the tolerance.
      expect(
        tops.reduce((a, b) => a > b ? a : b) -
            tops.reduce((a, b) => a < b ? a : b),
        lessThan(10),
        reason: 'tiles share one row',
      );
    });
  });
}
