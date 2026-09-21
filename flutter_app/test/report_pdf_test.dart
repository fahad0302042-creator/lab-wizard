import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/data/report_pdf.dart';
import 'package:lab_wizard/features/reports/domain/asset_reports.dart';
import 'package:lab_wizard/features/reports/domain/lab_profile.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';
import 'package:lab_wizard/features/reports/domain/report_stats.dart';
import 'package:lab_wizard/features/reports/domain/runout.dart';
import 'package:lab_wizard/features/reports/lab_profile_providers.dart';
import 'package:lab_wizard/features/settings/presentation/lab_profile_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 1×1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LabProfile', () {
    test('round-trips through JSON and tolerates junk', () {
      const profile = LabProfile(
        name: 'Chem Lab 2',
        contact: 'lab@example.org',
        address: 'Block B\nLahore',
        logoPath: '/tmp/logo.png',
      );
      expect(LabProfile.decode(profile.encode()), profile);
      expect(LabProfile.decode(null), const LabProfile());
      expect(LabProfile.decode('{not json'), const LabProfile());
      expect(LabProfile.decode('[1,2]'), const LabProfile());
      expect(LabProfile.decode('{"name":"X","logo_path":" "}').logoPath, isNull);
      expect(const LabProfile().isEmpty, isTrue);
      expect(profile.copyWith(clearLogo: true).logoPath, isNull);
      expect(profile.copyWith(name: 'Y').contact, 'lab@example.org');
    });

    test('is saved on the device and restored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(labProfileProvider.notifier)
          .save(const LabProfile(name: 'Chem Lab 2', contact: '0300'));
      final preferences = await SharedPreferences.getInstance();
      expect(
        LabProfile.decode(preferences.getString(LabProfileController.key)).name,
        'Chem Lab 2',
      );
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(labProfileProvider);
      await pumpEventQueue();
      expect(restored.read(labProfileProvider).contact, '0300');
      expect(await restored.read(labProfileProvider.notifier).logoBytes(), isNull);
    });
  });

  group('buildReportPdf', () {
    final today = DateTime(2026, 9, 21, 12);
    final range = ReportRange.lastDays(7, today: today);
    final logs = [
      for (var i = 0; i < 120; i++)
        ConsumptionLog(
          id: 'l$i',
          itemId: 'c1',
          itemType: ItemKind.chemical,
          action: i % 5 == 0 ? InventoryAction.restock : InventoryAction.consume,
          amount: 5,
          note: i % 7 == 0 ? 'Note with =formula and a long comment' : '',
          loggedAt: today.subtract(Duration(hours: i * 2)),
          createdAt: today,
        ),
    ];
    final acetone = Chemical(
      id: 'c1',
      name: 'Acetone',
      formula: 'C3H6O',
      unit: 'mL',
      quantity: 40,
      initialQuantity: 100,
      lowStockThreshold: 10,
      notes: '',
      qrCode: 'q',
      createdAt: DateTime(2026, 1, 1),
      expiryDate: DateTime(2026, 9, 10),
    );

    ReportPdfInput input({LabProfile profile = const LabProfile(), bool logo = false}) =>
        ReportPdfInput(
          profile: profile,
          logo: logo ? _png : null,
          kind: ItemKind.chemical,
          range: range,
          trend: TrendComparison.compute(
            range,
            logs,
            kind: ItemKind.chemical,
            unitOf: (_) => 'mL',
          ),
          logs: [
            for (final log in logs.where((log) => range.contains(log.loggedAt)))
              ReportPdfLog(
                at: log.loggedAt,
                item: 'Acetone',
                action: log.action.name,
                amount: '${formatQuantity(log.amount)} mL',
                note: log.note,
              ),
          ],
          runOut: runOutReportForChemicals([acetone], logs, now: today),
          damage: damageReport(
            range,
            logs,
            kind: ItemKind.chemical,
            nameOf: (_) => 'Acetone',
            unitOf: (_) => 'mL',
          ),
          expiry: expiryReport([acetone], now: today),
          healthyItems: 1,
          totalItems: 1,
          generatedAt: today,
        );

    test('produces a multi-page PDF with and without branding', () async {
      final plain = await buildReportPdf(input());
      expect(utf8.decode(plain.take(5).toList()), '%PDF-');
      final branded = await buildReportPdf(
        input(
          profile: const LabProfile(
            name: 'Chem Lab 2',
            contact: 'lab@example.org',
            address: 'Block B\nLahore',
          ),
          logo: true,
        ),
      );
      expect(utf8.decode(branded.take(5).toList()), '%PDF-');
      expect(branded.length, greaterThan(plain.length));
      // Dozens of rows spill onto a second page: the header repeats and the
      // footer numbers them.
      final pages = RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(branded));
      expect(pages.length, greaterThanOrEqualTo(2));
    });

    test('apparatus input with loans and services renders too', () async {
      final bytes = await buildReportPdf(
        ReportPdfInput(
          profile: const LabProfile(name: 'Lab'),
          kind: ItemKind.apparatus,
          range: ReportRange.month(2026, 9),
          trend: TrendComparison.compute(
            ReportRange.month(2026, 9),
            const [],
            kind: ItemKind.apparatus,
            unitOf: (_) => 'pcs',
          ),
          logs: const [],
          runOut: const RunOutReport(estimates: [], gaps: {}),
          damage: DamageReport(rows: const [], range: ReportRange.month(2026, 9)),
          loans: const LoanReport(overdue: [], openLoans: 2),
          services: const ServiceReport(due: [], openTasks: 1, completedInRange: 0),
          healthyItems: 0,
          totalItems: 0,
          generatedAt: today,
        ),
      );
      expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    });
  });

  group('LabProfileCard', () {
    testWidgets('edits are saved as you type and the logo can be picked', (
      tester,
    ) async {
      var picked = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LabProfileCard(
                  pickLogo: () async {
                    picked++;
                    return null;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-name')), 'Chem Lab 2');
      await tester.enterText(
        find.byKey(const Key('profile-contact')),
        'lab@example.org',
      );
      await tester.pumpAndSettle();
      final preferences = await SharedPreferences.getInstance();
      final stored = LabProfile.decode(
        preferences.getString(LabProfileController.key),
      );
      expect(stored.name, 'Chem Lab 2');
      expect(stored.contact, 'lab@example.org');
      expect(find.byKey(const Key('profile-remove-logo')), findsNothing);
      await tester.tap(find.byKey(const Key('profile-pick-logo')));
      await tester.pumpAndSettle();
      expect(picked, 1);
    });

    testWidgets('a stored profile fills the fields', (tester) async {
      SharedPreferences.setMockInitialValues({
        LabProfileController.key: const LabProfile(name: 'Restored').encode(),
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LabProfileCard(pickLogo: () async => null),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('profile-name'))).controller!.text,
        'Restored',
      );
    });
  });
}
