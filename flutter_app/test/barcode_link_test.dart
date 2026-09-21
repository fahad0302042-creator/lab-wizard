import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/scanner/domain/scan_resolver.dart';
import 'package:lab_wizard/features/scanner/presentation/link_barcode_sheet.dart';
import 'package:lab_wizard/features/scanner/scanner_providers.dart';
import 'package:mobile_scanner/mobile_scanner.dart' show BarcodeFormat;
import 'package:shared_preferences/shared_preferences.dart';

const _ean = '4006381333931';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed, {this.failWith});

  final InventoryState seed;
  final Object? failWith;
  final updates = <String>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> updateItem({
    required ItemKind type,
    required String id,
    required Map<String, dynamic> changes,
    bool force = false,
  }) async {
    if (failWith != null) throw failWith!;
    updates.add(
      '${type.name}:$id:${changes.keys.single}=${changes.values.single}',
    );
    state = state.copyWith(
      chemicals: [
        for (final item in state.chemicals)
          item.id == id && type == ItemKind.chemical
              ? Chemical.fromMap({...item.toMap(), ...changes})
              : item,
      ],
      apparatus: [
        for (final item in state.apparatus)
          item.id == id && type == ItemKind.apparatus
              ? Apparatus.fromMap({...item.toMap(), ...changes})
              : item,
      ],
    );
  }
}

Chemical _chemical(String id, String name, {String? barcode}) => Chemical(
  id: id,
  name: name,
  formula: 'X',
  unit: 'mL',
  quantity: 5,
  initialQuantity: 10,
  lowStockThreshold: 1,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  barcode: barcode,
);

Apparatus _apparatus(String id, String name, {String? barcode}) => Apparatus(
  id: id,
  name: name,
  category: 'glassware',
  quantity: 2,
  initialQuantity: 2,
  lowStockThreshold: 0,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  barcode: barcode,
);

Future<_FakeInventory> _pumpLink(
  WidgetTester tester, {
  required InventoryState seed,
  required List<ScanMatch?> results,
  Object? failWith,
  String code = _ean,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => fake = _FakeInventory(seed, failWith: failWith),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  results.add(
                    await showLinkBarcodeSheet(
                      context,
                      code: code,
                      formatLabel: 'EAN-13',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('models', () {
    test('barcode is optional, round-trips and is omitted when empty', () {
      final plain = _chemical('c1', 'Acetone');
      expect(plain.barcode, isNull);
      expect(plain.toMap().containsKey(barcodeColumn), isFalse);
      final linked = plain.copyWith(barcode: _ean);
      expect(linked.toMap()[barcodeColumn], _ean);
      expect(Chemical.fromMap(linked.toMap()).barcode, _ean);
      expect(
        Chemical.fromMap({...linked.toMap(), 'barcode': ''}).barcode,
        isNull,
      );
      expect(
        Chemical.fromMap({...linked.toMap(), 'barcode': null}).barcode,
        isNull,
      );

      final gear = _apparatus('a1', 'Beaker', barcode: 'CODE-1');
      expect(gear.toMap()[barcodeColumn], 'CODE-1');
      expect(Apparatus.fromMap(gear.toMap()).barcode, 'CODE-1');
      expect(
        _apparatus('a2', 'Flask').toMap().containsKey(barcodeColumn),
        isFalse,
      );
    });
  });

  group('resolver', () {
    final chemicals = [
      _chemical('c1', 'Acetone', barcode: _ean),
      _chemical('c2', 'Ethanol'),
    ];
    final apparatus = [_apparatus('a1', 'Beaker', barcode: 'CODE-1')];

    test('opens only explicitly linked codes', () {
      final chem = resolveScan(
        _ean,
        chemicals: chemicals,
        apparatus: apparatus,
      );
      expect(chem?.id, 'c1');
      expect(chem?.viaBarcode, isTrue);
      final gear = resolveScan(
        ' CODE-1 ',
        chemicals: chemicals,
        apparatus: apparatus,
      );
      expect(gear?.id, 'a1');
      expect(gear?.kind, ItemKind.apparatus);
      expect(
        resolveScan(
          '4006381333932',
          chemicals: chemicals,
          apparatus: apparatus,
        ),
        isNull,
      );
      // A Lab Wizard payload never falls through to the barcode lookup.
      expect(
        resolveScan(
          'labwizard:chemical:$_ean',
          chemicals: chemicals,
          apparatus: apparatus,
        ),
        isNull,
      );
      // Lab Wizard labels still win over links.
      expect(
        resolveScan('qr-c2', chemicals: chemicals, apparatus: apparatus)?.id,
        'c2',
      );
      expect(isLabWizardCode('labwizard:apparatus:x'), isTrue);
      expect(isLabWizardCode(_ean), isFalse);
      expect(barcodeFormatLabel(BarcodeFormat.ean13), 'EAN-13');
      expect(barcodeFormatLabel(BarcodeFormat.qrCode), 'QR code');
      expect(barcodeFormatLabel(null), 'barcode');
    });
  });

  group('product barcode preference', () {
    test('is off by default and persisted on the device', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(productBarcodesProvider), isFalse);
      await container.read(productBarcodesProvider.notifier).set(true);
      expect(container.read(productBarcodesProvider), isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(ProductBarcodesController.key), isTrue);

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(productBarcodesProvider);
      await pumpEventQueue();
      expect(restored.read(productBarcodesProvider), isTrue);
    });
  });

  group('link sheet', () {
    testWidgets('links an unknown code to the chosen item', (tester) async {
      final results = <ScanMatch?>[];
      final fake = await _pumpLink(
        tester,
        seed: InventoryState(
          chemicals: [_chemical('c1', 'Acetone'), _chemical('c2', 'Ethanol')],
          apparatus: [_apparatus('a1', 'Beaker')],
        ),
        results: results,
      );
      expect(find.text(_ean), findsOneWidget);
      expect(find.text('EAN-13'), findsOneWidget);
      expect(find.byKey(const Key('link-item-chemical-c1')), findsOneWidget);
      expect(find.byKey(const Key('link-item-apparatus-a1')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('link-search')), 'eth');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('link-item-chemical-c1')), findsNothing);
      expect(find.byKey(const Key('link-item-chemical-c2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('link-item-chemical-c2')));
      await tester.pumpAndSettle();
      expect(fake.updates, ['chemical:c2:barcode=$_ean']);
      expect(results.single?.id, 'c2');
      expect(results.single?.viaBarcode, isTrue);
      expect(find.byKey(const Key('link-search')), findsNothing);
    });

    testWidgets('moves a code that is already on another item', (tester) async {
      final results = <ScanMatch?>[];
      final fake = await _pumpLink(
        tester,
        seed: InventoryState(
          chemicals: [_chemical('c1', 'Acetone', barcode: _ean)],
          apparatus: [_apparatus('a1', 'Beaker')],
        ),
        results: results,
      );
      expect(
        find.textContaining('Currently linked to Acetone'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('link-item-apparatus-a1')));
      await tester.pumpAndSettle();
      expect(fake.updates, [
        'chemical:c1:barcode=null',
        'apparatus:a1:barcode=$_ean',
      ]);
      expect(results.single?.id, 'a1');
    });

    testWidgets('asks before replacing a different code on the item', (
      tester,
    ) async {
      final results = <ScanMatch?>[];
      final fake = await _pumpLink(
        tester,
        seed: InventoryState(
          apparatus: [_apparatus('a1', 'Beaker', barcode: 'OLD-1')],
        ),
        results: results,
      );
      expect(find.textContaining('linked: OLD-1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('link-item-apparatus-a1')));
      await tester.pumpAndSettle();
      expect(find.text('Replace the code on Beaker?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.updates, isEmpty);
      expect(results, isEmpty);

      await tester.tap(find.byKey(const Key('link-item-apparatus-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('link-replace')));
      await tester.pumpAndSettle();
      expect(fake.updates, ['apparatus:a1:barcode=$_ean']);
      expect(results.single?.id, 'a1');
    });

    testWidgets('a missing column becomes a migration hint, not a crash', (
      tester,
    ) async {
      final results = <ScanMatch?>[];
      await _pumpLink(
        tester,
        seed: InventoryState(chemicals: [_chemical('c1', 'Acetone')]),
        results: results,
        failWith: StateError(
          "Could not find the 'barcode' column of 'chemicals' in the schema cache",
        ),
      );
      await tester.tap(find.byKey(const Key('link-item-chemical-c1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('missing the newest columns'), findsOneWidget);
      expect(results, isEmpty);
      await tester.tap(find.byKey(const Key('link-not-now')));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });

  group('item sheet', () {
    testWidgets('shows the linked code and can unlink it', (tester) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _FakeInventory fake;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => fake = _FakeInventory(
                InventoryState(
                  chemicals: [_chemical('c1', 'Acetone', barcode: _ean)],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: FilledButton(
                    onPressed: () => showItemDetailSheet(
                      context,
                      ref,
                      ItemKind.chemical,
                      'c1',
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('barcode-unlink')));
      expect(find.text('Linked barcode $_ean'), findsOneWidget);
      await tester.tap(find.byKey(const Key('barcode-unlink')));
      await tester.pumpAndSettle();
      expect(fake.updates, ['chemical:c1:barcode=null']);
      expect(find.byKey(const Key('barcode-unlink')), findsNothing);
    });
  });
}
