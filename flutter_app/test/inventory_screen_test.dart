import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/core/widgets/notebook_widgets.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeededInventory extends InventoryController {
  _SeededInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;
}

const _names = [
  '2-propanol',
  'Acetone',
  'Benzene',
  'Chloroform',
  'Dichloromethane',
  'Ethanol',
  'Formaldehyde',
  'Glycerol',
  'Hydrochloric acid',
  'Isopropanol',
  'Jasmone',
  'Kerosene',
  'Lithium chloride',
  'Magnesium sulfate',
  'Nitric acid',
  'Oxalic acid',
  'Potassium iodide',
  'Rubidium chloride',
  'Sodium chloride',
  'Toluene',
  'Urea',
  'Vanillin',
  'Water (deionized)',
  'Xylene',
  'Yttrium oxide',
  'Zinc sulfate',
];

List<Chemical> _chemicals() => [
  for (var index = 0; index < _names.length; index++)
    Chemical(
      id: 'chem-$index',
      name: _names[index],
      formula: 'F$index',
      unit: 'mL',
      quantity: 100 - index.toDouble(),
      initialQuantity: 100,
      lowStockThreshold: 10,
      notes: '',
      qrCode: 'qr-$index',
      createdAt: DateTime(2026, 1, 1 + index),
    ),
];

Widget _app({required InventoryState state}) => ProviderScope(
  overrides: [inventoryProvider.overrideWith(() => _SeededInventory(state))],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: const InventoryScreen(kind: ItemKind.chemical),
  ),
);

Future<void> _pumpPhone(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(420, 840);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

ScrollPosition _listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  group('index letters', () {
    test('use the first Latin letter and group everything else under #', () {
      expect(indexLetterFor('hydrochloric acid'), 'H');
      expect(indexLetterFor('  Zinc'), 'Z');
      expect(indexLetterFor('2-propanol'), '#');
      expect(indexLetterFor(''), '#');
      expect(alphabetIndexLetters.length, 27);
    });
  });

  group('inventory shelf', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('UX-01: density toggle switches rows and persists', (
      tester,
    ) async {
      await _pumpPhone(
        tester,
        _app(state: InventoryState(chemicals: _chemicals())),
      );

      expect(find.byType(StockBar), findsWidgets);
      expect(find.byTooltip('Show compact rows'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inventory-density-toggle')));
      await tester.pumpAndSettle();

      expect(find.byType(StockBar), findsNothing);
      expect(find.byTooltip('Restock'), findsWidgets);
      expect(find.byTooltip('Use'), findsWidgets);
      expect(find.byTooltip('Show detailed cards'), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('inventory_density'), 'compact');
    });

    testWidgets('UX-01: compact preference is restored on launch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'inventory_density': 'compact'});
      await _pumpPhone(
        tester,
        _app(state: InventoryState(chemicals: _chemicals())),
      );
      expect(find.byType(StockBar), findsNothing);
      expect(find.byTooltip('Show detailed cards'), findsOneWidget);
    });

    testWidgets('UX-02: A–Z strip jumps to the first matching item', (
      tester,
    ) async {
      await _pumpPhone(
        tester,
        _app(state: InventoryState(chemicals: _chemicals())),
      );

      await tester.tap(find.byKey(const Key('alpha-M')));
      await tester.pumpAndSettle();

      final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final itemTop = tester.getTopLeft(find.text('Magnesium sulfate')).dy;
      expect(itemTop, greaterThanOrEqualTo(listTop));
      expect(itemTop - listTop, lessThan(80));

      final before = _listPosition(tester).pixels;
      await tester.tap(find.byKey(const Key('alpha-Q')));
      await tester.pumpAndSettle();
      expect(_listPosition(tester).pixels, before);
      final disabled = tester.widget<Text>(find.byKey(const Key('alpha-Q')));
      expect(disabled.style!.color!.a, lessThan(.5));
    });

    testWidgets('UX-02: strip follows search results and compact mode', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'inventory_density': 'compact'});
      await _pumpPhone(
        tester,
        _app(state: InventoryState(chemicals: _chemicals())),
      );

      await tester.tap(find.byKey(const Key('alpha-Z')));
      await tester.pumpAndSettle();
      // The last row cannot be aligned with the top of a short list: the
      // shelf scrolls as far as it can and the row is on screen.
      final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final listBottom = tester.getBottomLeft(find.byType(CustomScrollView)).dy;
      final zincTop = tester.getTopLeft(find.text('Zinc sulfate')).dy;
      expect(zincTop, greaterThanOrEqualTo(listTop));
      expect(zincTop, lessThan(listBottom));
      final position = _listPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));

      await tester.enterText(find.byType(TextField), 'chlor');
      await tester.pumpAndSettle();
      final zLetter = tester.widget<Text>(find.byKey(const Key('alpha-Z')));
      expect(zLetter.style!.color!.a, lessThan(.5));
      final sLetter = tester.widget<Text>(find.byKey(const Key('alpha-S')));
      expect(sLetter.style!.color!.a, 1);
    });

    testWidgets('UX-03: heading collapses while controls stay reachable', (
      tester,
    ) async {
      await _pumpPhone(
        tester,
        _app(state: InventoryState(chemicals: _chemicals())),
      );

      expect(find.text('chemicals shelf'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('chemicals shelf'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      // Filter row collapses while scrolling down to maximize visible inventory cards
      expect(find.text('all'), findsNothing);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(find.text('chemicals shelf'), findsOneWidget);
      expect(find.text('all'), findsOneWidget);
      expect(find.text('critical'), findsOneWidget);
      expect(find.textContaining('sort:'), findsOneWidget);
    });
  });
}
