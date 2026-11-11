import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/inventory/domain/models.dart';
import 'package:lab_wizard_v2/features/reports/data/report_organization.dart';
import 'package:lab_wizard_v2/features/reports/data/report_pdf.dart';
import 'package:lab_wizard_v2/features/reports/domain/monthly_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('name is saved, restored, and can be cleared', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ReportOrganization.load(), isEmpty);
    expect(await ReportOrganization.save('  Science   College  '),
        'Science College');
    expect(await ReportOrganization.load(), 'Science College');
    await ReportOrganization.save('  ');
    expect(await ReportOrganization.load(), isEmpty);
  });

  test('a long organization name can be used in the report header', () async {
    final report = MonthlyReport(
      kind: ItemKind.chemical,
      month: DateTime(2026, 10),
      rows: const [],
      events: 0,
      lowStockCount: 0,
    );
    final bytes = await ReportPdf.build(
      reports: [report],
      generatedAt: DateTime(2026, 11),
      organizationName: 'Lahore School of Science and Laboratory Research '
          'Department of Chemical Education',
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
