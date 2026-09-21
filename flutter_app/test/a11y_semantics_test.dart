import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/core/widgets/notebook_widgets.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeededInventory extends InventoryController {
  _SeededInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;
}

Chemical _chemical(
  String id,
  String name, {
  double quantity = 80,
  String formula = '',
  DateTime? expiryDate,
  List<HazardClass> hazards = const [],
}) => Chemical(
  id: id,
  name: name,
  formula: formula,
  unit: 'mL',
  quantity: quantity,
  initialQuantity: 100,
  lowStockThreshold: 20,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  expiryDate: expiryDate,
  hazardClasses: hazards.map((hazard) => hazard.code).toList(),
);

Apparatus _apparatus(String id, String name) => Apparatus(
  id: id,
  name: name,
  category: 'glassware',
  quantity: 3,
  initialQuantity: 3,
  lowStockThreshold: 1,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  condition: 'needs repair',
  assignedTo: 'Aisha',
);

Future<void> _pumpShelf(
  WidgetTester tester, {
  required InventoryState state,
  ItemKind kind = ItemKind.chemical,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(() => _SeededInventory(state)),
        isOnlineProvider.overrideWithValue(() async => true),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: InventoryScreen(kind: kind),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SemanticsNode _node(WidgetTester tester, Pattern label) =>
    tester.getSemantics(find.bySemanticsLabel(label));

bool _hasCustomAction(SemanticsNode node, String label) =>
    (node.getSemanticsData().customSemanticsActionIds ?? const []).contains(
      CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A11Y-01 spoken text', () {
    test('stock status is spoken without symbols', () {
      expect(stockSpoken(StockState.healthy), 'in stock');
      expect(stockSpoken(StockState.low), 'low stock');
      expect(stockSpoken(StockState.empty), 'out of stock');
      expect(stockCaption(StockState.healthy), contains('✓'));
    });

    test('activity chart summary names total, busiest bucket and gaps', () {
      final range = ReportRange.lastDays(7, today: DateTime(2026, 9, 21));
      expect(
        activityChartSummary(bucketize(range, const [])),
        'Activity chart: no activity in this range',
      );
      final summary = activityChartSummary(
        bucketize(range, [
          DateTime(2026, 9, 20, 9),
          DateTime(2026, 9, 20, 15),
          DateTime(2026, 9, 18, 8),
        ]),
      );
      expect(summary, startsWith('Activity chart: 3 actions over 7 days'));
      expect(summary, contains('busiest 20 September with 2'));
      expect(summary, contains('5 days with none'));
      expect(activityChartSummary(const []), contains('nothing to show'));
    });
  });

  group('A11Y-01 shelf semantics', () {
    final chemicals = [
      _chemical('c1', 'Acetone', quantity: 12, formula: 'C3H6O'),
      _chemical(
        'c2',
        'Benzene',
        formula: 'C6H6',
        expiryDate: DateTime(2020, 1, 1),
        hazards: const [HazardClass.flammable, HazardClass.toxic],
      ),
      _chemical('c3', 'Ethanol', quantity: 0),
    ];

    testWidgets('every tappable node on the shelf has a label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpShelf(tester, state: InventoryState(chemicals: chemicals));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byTooltip('Show compact rows'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('a card is one spoken item with use and restock actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpShelf(tester, state: InventoryState(chemicals: chemicals));

      final acetone = _node(tester, RegExp(r'^Acetone, 12 mL, low stock'));
      expect(acetone.label, 'Acetone, 12 mL, low stock, C3H6O');
      expect(acetone.flagsCollection.isButton, isTrue);
      expect(_hasCustomAction(acetone, 'Use'), isTrue);
      expect(_hasCustomAction(acetone, 'Restock'), isTrue);

      final benzene = _node(tester, RegExp(r'^Benzene'));
      expect(benzene.label, contains('expired'));
      expect(benzene.label, contains('hazards: flammable, toxic'));
      expect(_node(tester, RegExp(r'^Ethanol')).label, contains('out of stock'));

      // The heading is navigable as a heading.
      expect(_node(tester, 'chemicals shelf').flagsCollection.isHeader, isTrue);

      // The custom action opens the same sheet as the swipe or the button.
      tester.semantics.performAction(
        find.semantics.byLabel(RegExp(r'^Acetone')),
        SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Use'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('consume'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('compact rows and selection mode speak their state', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'inventory_density': 'compact'});
      final handle = tester.ensureSemantics();
      await _pumpShelf(tester, state: InventoryState(chemicals: chemicals));
      expect(find.byType(StockBar), findsNothing);
      final row = _node(tester, RegExp(r'^Acetone, 12 mL, low stock'));
      expect(_hasCustomAction(row, 'Use'), isTrue);

      await tester.longPress(find.text('Acetone'));
      await tester.pumpAndSettle();
      final selected = _node(tester, RegExp(r'^Acetone.*, selected$'));
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      expect(_hasCustomAction(selected, 'Use'), isFalse);
      expect(
        _node(
          tester,
          RegExp(r'^Benzene.*, not selected$'),
        ).flagsCollection.isSelected,
        Tristate.isFalse,
      );

      // A–Z strip: unavailable letters are disabled buttons, not silent text.
      final q = tester.getSemantics(find.byKey(const Key('alpha-Q')));
      expect(q.label, 'jump to Q');
      expect(q.flagsCollection.isEnabled, Tristate.isFalse);
      final a = tester.getSemantics(find.byKey(const Key('alpha-A')));
      expect(a.flagsCollection.isEnabled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('apparatus rows speak condition, assignee and damage action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpShelf(
        tester,
        kind: ItemKind.apparatus,
        state: InventoryState(apparatus: [_apparatus('a1', 'Balance')]),
      );
      final balance = _node(tester, RegExp(r'^Balance'));
      expect(
        balance.label,
        'Balance, 3 pcs, in stock, glassware, needs repair, assigned to Aisha',
      );
      expect(_hasCustomAction(balance, 'Report damage'), isTrue);
      expect(_hasCustomAction(balance, 'Use'), isFalse);
      handle.dispose();
    });
  });
}
