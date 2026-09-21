import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/diagnostics/diagnostics_providers.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/settings/presentation/diagnostics_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _SeededInventory extends InventoryController {
  _SeededInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;
}

class _FakeAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    phase: AuthPhase.signedIn,
    user: User.fromJson(<String, dynamic>{
      'id': 'u1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'aisha@university.edu.pk',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    }),
  );
}

class _TestDiagnostics extends DiagnosticsController {
  DateTime now = DateTime.utc(2026, 9, 21, 10);

  @override
  DateTime get clock => now;

  @override
  String get appBuild => '1.1.99';

  @override
  String get platform => 'android 14';
}

final _inventory = InventoryState(
  chemicals: [
    Chemical(
      id: 'c1',
      name: 'Acetone',
      formula: 'C3H6O',
      unit: 'mL',
      quantity: 40,
      initialQuantity: 100,
      lowStockThreshold: 10,
      notes: 'donated by Dr Malik',
      qrCode: 'qr-1',
      createdAt: DateTime(2026, 1, 1),
      supplier: 'Merck',
      location: 'Cabinet B',
      barcode: '4006381333931',
    ),
  ],
  apparatus: [
    Apparatus(
      id: 'a1',
      name: 'Balance',
      category: 'glassware',
      quantity: 1,
      initialQuantity: 1,
      lowStockThreshold: 0,
      notes: '',
      createdAt: DateTime(2026, 1, 1),
      assignedTo: 'Bilal',
      serialNumber: 'SN-777',
    ),
  ],
);

({ProviderContainer container, _TestDiagnostics diagnostics}) _harness() {
  late _TestDiagnostics diagnostics;
  final container = ProviderContainer(
    overrides: [
      inventoryProvider.overrideWith(() => _SeededInventory(_inventory)),
      authProvider.overrideWith(_FakeAuth.new),
      diagnosticsProvider.overrideWith(() => diagnostics = _TestDiagnostics()),
    ],
  );
  addTearDown(container.dispose);
  container.read(diagnosticsProvider);
  return (container: container, diagnostics: diagnostics);
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OBS-01 scrubber', () {
    test('removes known words, e-mails, tokens, query values, long digits', () {
      final scrubber = DiagnosticsScrubber([
        'Acetone',
        'donated by Dr Malik',
        'ab', // too short to be a word worth redacting
        '',
      ]);
      final out = scrubber.scrub(
        'Failed to save acetone (Acetone) for ali@example.org: '
        'Bearer abc.def.ghi at https://x.supabase.co/rest?apikey=SECRET123&x=1 '
        'barcode 4006381333931 token '
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJlc2lnbmF0dXJl '
        'note "donated by Dr Malik" abracadabra',
      );
      expect(out, isNot(contains('Acetone')));
      expect(out, isNot(contains('acetone')));
      expect(out, isNot(contains('ali@example.org')));
      expect(out, isNot(contains('SECRET123')));
      expect(out, isNot(contains('4006381333931')));
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, isNot(contains('Dr Malik')));
      expect(out, contains('[redacted]'));
      expect(out, contains('[email]'));
      expect(out, contains('[digits]'));
      expect(out, contains('apikey=[redacted]'));
      expect(out, contains('abracadabra'), reason: 'short words are kept');
      expect(out, contains('https://x.supabase.co/rest'));
    });

    test('keeps the top of a stack trace', () {
      final scrubber = DiagnosticsScrubber(const []);
      final stack = List.generate(
        80,
        (i) => '#$i      Frame$i (package:lab_wizard/a.dart:$i:1)',
      ).join('\n');
      final out = scrubber.scrubStack(stack);
      expect(out.split('\n'), hasLength(diagnosticsStackLines + 1));
      expect(out, contains('#0      Frame0'));
      expect(out, contains('40 more frames'));
      expect(out, isNot(contains('Frame79')));
    });
  });

  group('OBS-01 retention', () {
    DiagnosticReport report(String id, DateTime at) => DiagnosticReport(
      id: id,
      at: at,
      kind: DiagnosticKind.handled,
      message: 'm',
      stack: '',
      context: '',
      appBuild: 'dev',
      platform: 'test',
    );

    test('drops old reports and caps the count, newest first', () {
      final now = DateTime.utc(2026, 9, 21);
      final reports = [
        report('old', now.subtract(const Duration(days: 15))),
        for (var i = 0; i < 40; i++)
          report('r$i', now.subtract(Duration(hours: i))),
      ];
      final kept = pruneDiagnostics(reports, now);
      expect(kept, hasLength(diagnosticsLimit));
      expect(kept.first.id, 'r0');
      expect(kept.map((r) => r.id), isNot(contains('old')));
      expect(kept.map((r) => r.id), isNot(contains('r39')));
    });

    test('round-trips through JSON and survives junk', () {
      final now = DateTime.utc(2026, 9, 21, 8, 30);
      final encoded = encodeDiagnostics([report('a', now)]);
      final decoded = decodeDiagnostics(encoded);
      expect(decoded.single.id, 'a');
      expect(decoded.single.at, now);
      expect(decodeDiagnostics('not json'), isEmpty);
      expect(decodeDiagnostics(null), isEmpty);
      expect(DiagnosticKind.parse('nonsense'), DiagnosticKind.handled);
    });
  });

  group('OBS-01 controller', () {
    test('records nothing while off, scrubbed reports while on', () async {
      final h = _harness();
      await _settle();
      expect(h.container.read(diagnosticsProvider).ready, isTrue);
      expect(h.container.read(diagnosticsProvider).enabled, isFalse);

      await h.diagnostics.record(
        StateError('Could not update Acetone in Cabinet B'),
        stack: StackTrace.current,
      );
      expect(h.container.read(diagnosticsProvider).reports, isEmpty);

      await h.diagnostics.setEnabled(true);
      await h.diagnostics.record(
        StateError(
          'Could not update Acetone in Cabinet B for aisha@university.edu.pk '
          '(Merck, SN-777, Bilal, donated by Dr Malik)',
        ),
        stack: StackTrace.current,
        context: 'while saving Balance',
      );
      final state = h.container.read(diagnosticsProvider);
      expect(state.reports, hasLength(1));
      final report = state.reports.single;
      expect(report.kind, DiagnosticKind.handled);
      expect(report.message, isNot(contains('Acetone')));
      expect(report.message, isNot(contains('Cabinet B')));
      expect(report.message, isNot(contains('aisha@')));
      expect(report.message, isNot(contains('Merck')));
      expect(report.message, isNot(contains('SN-777')));
      expect(report.message, isNot(contains('Bilal')));
      expect(report.message, isNot(contains('Malik')));
      expect(report.message, contains('Could not update [redacted]'));
      expect(report.context, 'while saving [redacted]');
      expect(report.stack, contains('diagnostics_test.dart'));
      expect(report.appBuild, '1.1.99');
      expect(report.platform, 'android 14');

      // Persisted and restored by a fresh controller.
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(diagnosticsEnabledKey), isTrue);
      final again = _harness();
      await _settle();
      final restored = again.container.read(diagnosticsProvider);
      expect(restored.enabled, isTrue);
      expect(restored.reports.single.id, report.id);

      // Export is readable JSON; clear removes everything.
      final exported =
          jsonDecode(again.diagnostics.exportJson()) as Map<String, dynamic>;
      expect(exported['build'], '1.1.99');
      expect(exported['retention_days'], diagnosticsRetention.inDays);
      expect((exported['reports'] as List), hasLength(1));
      await again.diagnostics.clear();
      expect(again.container.read(diagnosticsProvider).reports, isEmpty);
      expect(preferences.getString(diagnosticsReportsKey), isNull);
    });

    test('Flutter errors are recorded with their context', () async {
      final h = _harness();
      await _settle();
      await h.diagnostics.setEnabled(true);
      await h.diagnostics.recordFlutterError(
        FlutterErrorDetails(
          exception: FlutterError('A RenderFlex overflowed by 12 pixels'),
          stack: StackTrace.current,
          library: 'rendering library',
          context: ErrorDescription('during layout of Acetone card'),
        ),
      );
      final report = h.container.read(diagnosticsProvider).reports.single;
      expect(report.kind, DiagnosticKind.flutter);
      expect(report.message, contains('RenderFlex overflowed'));
      expect(report.context, 'during layout of [redacted] card');
      expect(report.headline, startsWith('A RenderFlex overflowed'));
    });

    test('a newer report pushes old ones out', () async {
      final h = _harness();
      await _settle();
      await h.diagnostics.setEnabled(true);
      for (var i = 0; i < diagnosticsLimit + 3; i++) {
        h.diagnostics.now = h.diagnostics.now.add(const Duration(minutes: 1));
        await h.diagnostics.record('error $i');
      }
      final reports = h.container.read(diagnosticsProvider).reports;
      expect(reports, hasLength(diagnosticsLimit));
      expect(reports.first.message, 'error ${diagnosticsLimit + 2}');
      h.diagnostics.now = h.diagnostics.now.add(const Duration(days: 15));
      await h.diagnostics.record('fresh');
      expect(
        h.container.read(diagnosticsProvider).reports.single.message,
        'fresh',
      );
    });
  });

  group('OBS-01 settings card', () {
    testWidgets('explains, opts in, lists, shares and deletes', (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late _TestDiagnostics diagnostics;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(() => _SeededInventory(_inventory)),
            authProvider.overrideWith(_FakeAuth.new),
            diagnosticsProvider.overrideWith(
              () => diagnostics = _TestDiagnostics(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: DiagnosticsCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Off by default'), findsOneWidget);
      expect(find.textContaining('14 days'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.byKey(const Key('diagnostics-share')), findsNothing);

      await tester.tap(find.byKey(const Key('diagnostics-enabled')));
      await tester.pumpAndSettle();
      expect(find.text('0 stored'), findsOneWidget);

      await diagnostics.record('Something about Acetone broke');
      await tester.pumpAndSettle();
      expect(find.text('1 stored'), findsOneWidget);
      expect(
        find.textContaining('Something about [redacted] broke'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('diagnostics-share')), findsOneWidget);

      await tester.tap(find.byKey(const Key('diagnostics-clear')));
      await tester.pumpAndSettle();
      expect(find.text('0 stored'), findsOneWidget);
      expect(find.byKey(const Key('diagnostics-share')), findsNothing);
    });
  });
}
