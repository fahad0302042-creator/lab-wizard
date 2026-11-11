import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/inventory/domain/models.dart';
import 'package:lab_wizard_v2/features/reports/data/report_pdf.dart';
import 'package:lab_wizard_v2/features/reports/domain/monthly_report.dart';

void main() {
  test('PDF can be built with and without a logo', () async {
    final report = MonthlyReport(
      kind: ItemKind.chemical,
      month: DateTime(2026, 10),
      rows: const [],
      events: 0,
      lowStockCount: 0,
    );
    final logo = await File('assets/images/logo.png').readAsBytes();
    final plain = await ReportPdf.build(
      reports: [report],
      generatedAt: DateTime(2026, 11),
    );
    final branded = await ReportPdf.build(
      reports: [report],
      generatedAt: DateTime(2026, 11),
      logoBytes: logo,
    );
    expect(String.fromCharCodes(plain.take(4)), '%PDF');
    expect(String.fromCharCodes(branded.take(4)), '%PDF');
    expect(branded.length, greaterThan(plain.length));
  });
}
