import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/scanner/domain/recent_scan.dart';
import 'package:lab_wizard/features/scanner/domain/scan_resolver.dart';
import 'package:lab_wizard/features/scanner/presentation/recent_scans_section.dart';
import 'package:lab_wizard/features/scanner/scanner_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

final _now = DateTime(2026, 9, 21, 10);

User _user(String id) => User.fromJson(<String, dynamic>{
  'id': id,
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'created_at': '2026-01-01T00:00:00Z',
})!;

class _FakeAuth extends AuthController {
  _FakeAuth(this.userId);

  final String userId;

  @override
  AuthState build() =>
      AuthState(phase: AuthPhase.signedIn, user: _user(userId));
}

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}
}

Chemical _chemical(String id, String code) => Chemical(
  id: id,
  name: 'Ethanol $id',
  formula: 'C2H6O',
  unit: 'mL',
  quantity: 40,
  initialQuantity: 100,
  lowStockThreshold: 10,
  notes: '',
  qrCode: code,
  createdAt: DateTime(2026, 1, 1),
);

Apparatus _apparatus(String id) => Apparatus(
  id: id,
  name: 'Burette $id',
  category: 'volumetric_glass',
  quantity: 4,
  initialQuantity: 4,
  lowStockThreshold: 1,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
);

RecentScan _found(ItemKind kind, String id, {int minutesAgo = 0}) => RecentScan(
  raw: 'labwizard:${kind.name}:$id',
  scannedAt: _now.subtract(Duration(minutes: minutesAgo)),
  kind: kind,
  itemId: id,
  name: kind == ItemKind.chemical ? 'Ethanol $id' : 'Burette $id',
  subtitle: kind == ItemKind.chemical ? 'C2H6O' : 'volumetric glass',
);

ProviderContainer _container(String userId) {
  final container = ProviderContainer(
    overrides: [authProvider.overrideWith(() => _FakeAuth(userId))],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required InventoryState seed,
  String userId = 'u1',
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(userId)),
        inventoryProvider.overrideWith(() => _FakeInventory(seed)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RecentScansSection(collapsedCount: 2),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('scan resolver', () {
    final chemicals = [_chemical('c1', 'code-1'), _chemical('c2', 'code-2')];
    final apparatus = [_apparatus('a1')];

    test('matches prefixed and legacy chemical codes', () {
      final prefixed = resolveScan(
        'labwizard:chemical:code-2',
        chemicals: chemicals,
        apparatus: apparatus,
      );
      expect(prefixed?.kind, ItemKind.chemical);
      expect(prefixed?.id, 'c2');
      expect(prefixed?.subtitle, 'C2H6O');
      final legacy = resolveScan(
        ' code-1 \n',
        chemicals: chemicals,
        apparatus: apparatus,
      );
      expect(legacy?.id, 'c1');
    });

    test('matches apparatus by id and never falls back to chemicals', () {
      final match = resolveScan(
        'labwizard:apparatus:a1',
        chemicals: chemicals,
        apparatus: apparatus,
      );
      expect(match?.kind, ItemKind.apparatus);
      expect(match?.name, 'Burette a1');
      expect(match?.subtitle, 'volumetric glass');
      expect(
        resolveScan(
          'labwizard:apparatus:code-1',
          chemicals: chemicals,
          apparatus: apparatus,
        ),
        isNull,
      );
      expect(
        resolveScan(
          'https://example.com',
          chemicals: chemicals,
          apparatus: apparatus,
        ),
        isNull,
      );
      expect(
        resolveScan('   ', chemicals: chemicals, apparatus: apparatus),
        isNull,
      );
      expect(
        resolveScan(
          'labwizard:chemical:',
          chemicals: chemicals,
          apparatus: apparatus,
        ),
        isNull,
      );
    });
  });

  group('recent scan history', () {
    test('round-trips through JSON and dedupes per item', () {
      final found = _found(ItemKind.apparatus, 'a1');
      final unknown = RecentScan.unknown('https://example.com', _now);
      final restored = decodeRecentScans(encodeRecentScans([found, unknown]));
      expect(restored, hasLength(2));
      expect(restored.first.found, isTrue);
      expect(restored.first.kind, ItemKind.apparatus);
      expect(restored.first.itemId, 'a1');
      expect(restored.first.name, 'Burette a1');
      expect(restored.first.scannedAt, _now);
      expect(restored.last.found, isFalse);
      expect(restored.last.raw, 'https://example.com');
      expect(decodeRecentScans('not json'), isEmpty);
      expect(decodeRecentScans('{"a":1}'), isEmpty);

      var history = pushRecentScan(const [], found);
      history = pushRecentScan(history, unknown);
      history = pushRecentScan(
        history,
        _found(ItemKind.apparatus, 'a1', minutesAgo: -5),
      );
      expect(history.map((scan) => scan.dedupeKey), [
        'apparatus:a1',
        'raw:https://example.com',
      ]);
      for (var index = 0; index < 40; index++) {
        history = pushRecentScan(history, _found(ItemKind.chemical, 'c$index'));
      }
      expect(history, hasLength(recentScansLimit));
      expect(history.first.itemId, 'c39');
    });

    test('is persisted per user and restored on the next start', () async {
      final first = _container('u1');
      final controller = first.read(recentScansProvider.notifier);
      await controller.record(_found(ItemKind.chemical, 'c1', minutesAgo: 3));
      await controller.record(_found(ItemKind.apparatus, 'a1'));
      expect(first.read(recentScansProvider).map((scan) => scan.itemId), [
        'a1',
        'c1',
      ]);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(recentScansKey('u1')), isNotNull);

      final second = _container('u1');
      expect(second.read(recentScansProvider), isEmpty);
      await pumpEventQueue();
      expect(second.read(recentScansProvider).map((scan) => scan.itemId), [
        'a1',
        'c1',
      ]);

      final other = _container('u2');
      await pumpEventQueue();
      expect(other.read(recentScansProvider), isEmpty);

      await second.read(recentScansProvider.notifier).clear();
      expect(second.read(recentScansProvider), isEmpty);
      expect(preferences.getString(recentScansKey('u1')), isNull);
    });

    test('scans recorded while loading are kept in front', () async {
      SharedPreferences.setMockInitialValues({
        recentScansKey('u1'): encodeRecentScans([
          _found(ItemKind.chemical, 'c1', minutesAgo: 10),
          _found(ItemKind.chemical, 'c2', minutesAgo: 20),
        ]),
      });
      final container = _container('u1');
      final controller = container.read(recentScansProvider.notifier);
      await controller.record(_found(ItemKind.chemical, 'c2'));
      await pumpEventQueue();
      expect(container.read(recentScansProvider).map((scan) => scan.itemId), [
        'c2',
        'c1',
      ]);
    });
  });

  group('recent scans section', () {
    testWidgets('lists scans, opens items, flags removed and unknown ones', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        recentScansKey('u1'): encodeRecentScans([
          _found(ItemKind.apparatus, 'a1'),
          _found(ItemKind.chemical, 'gone', minutesAgo: 2),
          RecentScan.unknown(
            'https://example.com/very/long/path/that/keeps/going',
            _now.subtract(const Duration(minutes: 4)),
          ),
        ]),
      });
      await _pumpSection(
        tester,
        seed: InventoryState(
          apparatus: [_apparatus('a1')],
          chemicals: [_chemical('c1', 'code-1')],
        ),
      );
      expect(find.text('recent scans'), findsOneWidget);
      expect(find.text('Burette a1'), findsOneWidget);
      expect(find.text('Ethanol gone'), findsOneWidget);
      expect(find.text('removed'), findsOneWidget);
      expect(find.text('Unknown code'), findsNothing);
      expect(find.text('show all 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('recent-scans-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Unknown code'), findsOneWidget);
      expect(find.text('not matched'), findsOneWidget);
      expect(find.text('show fewer'), findsOneWidget);

      await tester.tap(find.text('Ethanol gone'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ethanol gone is no longer in your notebook.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Unknown code'));
      await tester.pumpAndSettle();
      expect(find.text('Code not in your notebook'), findsOneWidget);
      expect(
        find.text('https://example.com/very/long/path/that/keeps/going'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Burette a1'));
      await tester.pumpAndSettle();
      expect(find.text('Burette a1'), findsWidgets);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('clear asks first and empties the stored history', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        recentScansKey('u1'): encodeRecentScans([
          _found(ItemKind.apparatus, 'a1'),
        ]),
      });
      await _pumpSection(
        tester,
        seed: InventoryState(apparatus: [_apparatus('a1')]),
      );
      expect(find.text('Burette a1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recent-scans-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Burette a1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('recent-scans-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recent-scans-clear-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Burette a1'), findsNothing);
      expect(find.text('recent scans'), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(recentScansKey('u1')), isNull);
    });
  });
}
