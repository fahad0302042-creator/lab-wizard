import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/home/presentation/dashboard_screen.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'support/fixtures.dart';

/// TEST-03: every supported width and orientation combined with enlarged
/// text. Any overflow fails the test; the single-size checks live in
/// responsive_layout_test.dart (widths) and large_text_test.dart (200 %).
const _sizes = <String, Size>{
  'small phone': Size(320, 568),
  'phone landscape': Size(740, 360),
  'small tablet': Size(600, 960),
  'tablet landscape': Size(1024, 720),
};
const _scales = [1.3, 2.0];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in _sizes.entries) {
    for (final scale in _scales) {
      final label = '${size.key} at ${(scale * 100).round()} %';

      testWidgets('$label: shelf in both densities', (tester) async {
        await pumpScreen(
          tester,
          const InventoryScreen(kind: ItemKind.chemical),
          size: size.value,
          scale: scale,
        );
        expect(find.text('Ethanol'), findsOneWidget);
        await tester.tap(find.byTooltip('Show compact rows'));
        await tester.pumpAndSettle();
        expect(find.text('Ethanol'), findsOneWidget);
      });

      testWidgets('$label: dashboard', (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: DashboardScreen(
              user: User.fromJson(userJson)!,
              onNavigate: (_) {},
              onSettings: () {},
            ),
          ),
          size: size.value,
          scale: scale,
        );
        await tester.scrollUntilVisible(
          find.text('actions this week'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('actions this week'), findsOneWidget);
      });

      testWidgets('$label: item detail sheet', (tester) async {
        await pumpScreen(
          tester,
          sheetOpener(
            (context, ref) =>
                showItemDetailSheet(context, ref, ItemKind.chemical, 'c1'),
          ),
          size: size.value,
          scale: scale,
        );
        await openSheet(tester);
        expect(find.textContaining('Hydrochloric'), findsWidgets);
      });
    }
  }
}
