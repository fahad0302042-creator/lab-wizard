import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/scanner/domain/scan_batch.dart';
import 'package:lab_wizard/features/scanner/domain/scan_resolver.dart';
import 'package:lab_wizard/features/scanner/presentation/batch_summary_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 9, 21, 10);

const _acid = ScanMatch(
  kind: ItemKind.chemical,
  id: 'c1',
  name: 'Hydrochloric acid',
  subtitle: 'HCl',
);
const _flask = ScanMatch(
  kind: ItemKind.apparatus,
  id: 'a1',
  name: 'Volumetric flask',
  subtitle: 'glassware',
);

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('scan batch', () {
    test('collects items, counts repeats and keeps unknown codes', () {
      var batch = const ScanBatch();
      expect(batch.isEmpty, isTrue);

      final (afterAcid, first) = batch.add(
        'labwizard:chemical:code-1',
        _acid,
        at: _now,
      );
      expect(first, ScanBatchOutcome.added);
      expect(afterAcid.startedAt, _now);
      batch = afterAcid;

      final (afterFlask, second) = batch.add(
        'labwizard:apparatus:a1',
        _flask,
        at: _now.add(const Duration(seconds: 5)),
      );
      expect(second, ScanBatchOutcome.added);
      batch = afterFlask;

      final (afterRepeat, third) = batch.add(
        'labwizard:chemical:code-1',
        _acid,
        at: _now.add(const Duration(seconds: 9)),
      );
      expect(third, ScanBatchOutcome.duplicate);
      batch = afterRepeat;

      final (afterUnknown, fourth) = batch.add(
        ' https://example.com ',
        null,
        at: _now.add(const Duration(seconds: 12)),
      );
      expect(fourth, ScanBatchOutcome.unknown);
      final (finished, fifth) = afterUnknown.add(
        'https://example.com',
        null,
        at: _now.add(const Duration(seconds: 13)),
      );
      expect(fifth, ScanBatchOutcome.unknown);
      batch = finished;

      expect(batch.entries.map((entry) => entry.match.id), ['c1', 'a1']);
      expect(batch.entries.first.count, 2);
      expect(batch.entries.first.firstAt, _now);
      expect(batch.entries.first.lastAt, _now.add(const Duration(seconds: 9)));
      expect(batch.entries.last.count, 1);
      expect(batch.unknown, {'https://example.com': 2});
      expect(batch.itemCount, 2);
      expect(batch.unknownCount, 2);
      expect(batch.scanCount, 5);
      expect(batch.duplicateCount, 2);
      expect(batch.summaryLine, '2 items · 5 scans · 2 unknown');
      expect(batch.startedAt, _now);
      expect(
        const ScanBatch().add('x', _flask, at: _now).$1.summaryLine,
        '1 item · 1 scan',
      );
    });
  });

  group('batch summary sheet', () {
    testWidgets('lists entries with counts, opens items and reports done', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var batch = const ScanBatch().add('a', _acid, at: _now).$1;
      batch = batch.add('a', _acid, at: _now).$1;
      batch = batch.add('b', _flask, at: _now).$1;
      batch = batch.add('https://example.com', null, at: _now).$1;

      final results = <bool>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(
                InventoryState(
                  apparatus: [
                    Apparatus(
                      id: 'a1',
                      name: 'Volumetric flask',
                      category: 'glassware',
                      quantity: 3,
                      initialQuantity: 3,
                      lowStockThreshold: 1,
                      notes: '',
                      createdAt: DateTime(2026, 1, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      results.add(await showBatchSummarySheet(context, batch));
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
      expect(find.text('2 items · 4 scans · 1 unknown'), findsOneWidget);
      expect(
        find.text('1 repeated read counted, not listed twice.'),
        findsOneWidget,
      );
      expect(find.text('Hydrochloric acid'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(find.text('Volumetric flask'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('batch-entry-apparatus-a1')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNWidgets(2));
      expect(find.text('Volumetric flask'), findsWidgets);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.byKey(const Key('batch-keep-scanning')));
      await tester.pumpAndSettle();
      expect(results, [false]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-done')));
      await tester.pumpAndSettle();
      expect(results, [false, true]);
    });
  });
}
