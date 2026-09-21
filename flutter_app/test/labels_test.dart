import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/labels/domain/label_sheet.dart';
import 'package:lab_wizard/features/labels/domain/label_spec.dart';
import 'package:lab_wizard/features/labels/presentation/label_actions.dart';
import 'package:lab_wizard/features/labels/presentation/label_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}
}

Chemical _chemical(String id, {String qrCode = 'qr'}) => Chemical(
  id: id,
  name: 'Acetone $id',
  formula: 'C3H6O',
  unit: 'mL',
  quantity: 50,
  initialQuantity: 100,
  lowStockThreshold: 10,
  notes: '',
  qrCode: qrCode,
  createdAt: DateTime(2026, 1, 1),
);

Apparatus _apparatus(String id, {String? serial}) => Apparatus(
  id: id,
  name: 'Beaker 250 mL $id',
  category: 'glassware',
  quantity: 12,
  initialQuantity: 12,
  lowStockThreshold: 2,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  serialNumber: serial,
);

Future<void> _pumpShelf(
  WidgetTester tester, {
  required ItemKind kind,
  required InventoryState seed,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(() => _FakeInventory(seed)),
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('QR-02 label specs', () {
    test(
      'chemical labels keep the web app payload; blank codes are skipped',
      () {
        final labels = chemicalLabels([
          _chemical('c1', qrCode: 'abc-123'),
          _chemical('c2', qrCode: ''),
          _chemical('c3', qrCode: '  '),
        ]);
        expect(labels, hasLength(1));
        expect(labels.single.data, 'labwizard:chemical:abc-123');
        expect(labels.single.title, 'Acetone c1');
        expect(labels.single.subtitle, 'C3H6O');
        expect(labels.single.detail, isEmpty);
        expect(labels.single.fileStem, 'acetone-c1');
      },
    );

    test('apparatus labels use the stable row id plus a readable short id', () {
      final label = LabelSpec.apparatus(
        _apparatus('8f1c2b3a-1111-2222-3333-abcdef012345', serial: 'SN-42'),
      );
      expect(
        label.data,
        'labwizard:apparatus:8f1c2b3a-1111-2222-3333-abcdef012345',
      );
      expect(label.kind, ItemKind.apparatus);
      expect(label.subtitle, 'glassware · S/N SN-42');
      expect(label.detail, 'ID EF012345');
      expect(LabelSpec.apparatus(_apparatus('a1')).subtitle, 'glassware');
      expect(shortId('abc'), 'ABC');
      expect(
        apparatusLabels([_apparatus('a1'), _apparatus('a2')]),
        hasLength(2),
      );
    });
  });

  group('QR-02 label sheets', () {
    test('page counts follow the chosen grid', () {
      expect(labelPageCount(0, LabelSheetLayout.small), 0);
      expect(labelPageCount(40, LabelSheetLayout.small), 1);
      expect(labelPageCount(41, LabelSheetLayout.small), 2);
      expect(labelPageCount(24, LabelSheetLayout.medium), 1);
      expect(labelPageCount(25, LabelSheetLayout.medium), 2);
      expect(labelPageCount(12, LabelSheetLayout.large), 1);
      expect(labelPageCount(13, LabelSheetLayout.large), 2);
      expect(LabelSheetLayout.small.perPage, 40);
    });

    test('an A4 sheet holds 40 labels per page and renders to PDF', () async {
      final labels = [
        for (var index = 0; index < 41; index++)
          LabelSpec.apparatus(_apparatus('a$index', serial: 'S$index')),
      ];
      final document = buildLabelSheet(labels);
      final bytes = await document.save();
      expect(document.document.pdfPageList.pages, hasLength(2));
      expect(utf8.decode(bytes.take(5).toList()), '%PDF-');

      final large = buildLabelSheet(labels, layout: LabelSheetLayout.large);
      await large.save();
      expect(large.document.pdfPageList.pages, hasLength(4));

      final single = buildSingleLabel(labels.first);
      final singleBytes = await single.save();
      expect(single.document.pdfPageList.pages, hasLength(1));
      expect(singleBytes, isNotEmpty);
    });
  });

  group('QR-03 label image', () {
    testWidgets('renders a PNG of the expected size', (tester) async {
      final label = LabelSpec.chemical(_chemical('c1', qrCode: 'abc'));
      final bytes = (await tester.runAsync(
        () => renderLabelPng(label, width: 480),
      ))!;
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final image = (await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        return frame.image;
      }))!;
      expect(image.width, 480);
      expect(image.height, 300);
      image.dispose();
    });

    testWidgets('item sheet shows the label preview with share actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(
                InventoryState(apparatus: [_apparatus('a1', serial: 'SN-1')]),
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
                      ItemKind.apparatus,
                      'a1',
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
      await tester.ensureVisible(find.byKey(const Key('label-share-image')));
      expect(find.byType(LabelPreview), findsOneWidget);
      expect(find.byKey(const Key('label-share-pdf')), findsOneWidget);
      expect(find.byKey(const Key('label-print')), findsOneWidget);
      final preview = tester.widget<LabelPreview>(find.byType(LabelPreview));
      expect(preview.label.data, 'labwizard:apparatus:a1');
      expect(preview.label.subtitle, 'glassware · S/N SN-1');
    });
  });

  group('QR-02 sheet dialog and apparatus shelf', () {
    testWidgets('dialog previews pages per layout and returns the choice', (
      tester,
    ) async {
      LabelSheetChoice? choice;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    choice = await showLabelSheetDialog(context, count: 41);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('41 QR labels on A4'), findsOneWidget);
      expect(find.textContaining('2 pages'), findsOneWidget);
      await tester.tap(find.byKey(const Key('label-layout-large')));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 pages'), findsOneWidget);
      await tester.tap(find.byKey(const Key('label-sheet-share')));
      await tester.pumpAndSettle();
      expect(choice?.layout, LabelSheetLayout.large);
      expect(choice?.action, LabelSheetAction.share);
    });

    testWidgets('apparatus selection offers labels and the menu prints all', (
      tester,
    ) async {
      await _pumpShelf(
        tester,
        kind: ItemKind.apparatus,
        seed: InventoryState(apparatus: [_apparatus('a1'), _apparatus('a2')]),
      );
      await tester.longPress(find.text('Beaker 250 mL a1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-labels')), findsOneWidget);
      await tester.tap(find.byKey(const Key('selection-labels')));
      await tester.pumpAndSettle();
      expect(find.text('1 QR label on A4'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('selection-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Shelf actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-print-labels')));
      await tester.pumpAndSettle();
      expect(find.text('2 QR labels on A4'), findsOneWidget);
      // Printing goes through a platform channel that does not exist in
      // tests; the failure must surface as a message, not a crash.
      await tester.tap(find.byKey(const Key('label-sheet-print')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not export'), findsOneWidget);
    });
  });
}
