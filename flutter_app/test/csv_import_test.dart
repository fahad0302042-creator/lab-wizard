import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/import/domain/csv_parser.dart';
import 'package:lab_wizard/features/import/domain/import_plan.dart';
import 'package:lab_wizard/features/import/presentation/import_screen.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed, {this.failFor = const {}});

  final InventoryState seed;
  final Set<String> failFor;
  final addedChemicals = <(String, String, double, ChemicalDetails)>[];
  final addedApparatus = <(String, String, double)>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> addChemical({
    required String name,
    required String formula,
    required String unit,
    required double quantity,
    required double threshold,
    required String notes,
    ChemicalDetails details = const ChemicalDetails(),
  }) async {
    if (failFor.contains(name)) throw StateError('permission denied');
    addedChemicals.add((name, unit, quantity, details));
  }

  @override
  Future<void> addApparatus({
    required String name,
    required String category,
    required double quantity,
    required double threshold,
    required String notes,
  }) async {
    if (failFor.contains(name)) throw StateError('permission denied');
    addedApparatus.add((name, category, quantity));
  }
}

final _acetone = Chemical(
  id: 'chem-acetone',
  name: 'Acetone',
  formula: 'C3H6O',
  unit: 'mL',
  quantity: 400,
  initialQuantity: 500,
  lowStockThreshold: 50,
  notes: '',
  qrCode: 'qr-acetone',
  createdAt: DateTime(2026, 1, 1),
);

const _exportCsv =
    'type,name,formula/category,quantity,unit,low stock level,notes,'
    'supplier,cas number,concentration,location,expiry date,hazards\n'
    'chemical,Ethanol,C2H5OH,500,mL,50,"96%, food grade",Merck,64-17-5,96%,'
    'Cabinet B,2030-01-31,GHS02;GHS07\n'
    'chemical,acetone,C3H6O,100,mL,10,,,,,,,\n'
    'chemical,Broken row,X,lots,mL,,,,,,,,\n'
    'apparatus,Beaker 250 mL,glassware,12,pcs,2,,,,,,,\n'
    'apparatus,Hot plate,heating,1.5,pcs,0,,,,,,,\n';

Future<_FakeInventory> _pump(
  WidgetTester tester, {
  required String csv,
  Set<String> failFor = const {},
}) async {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FakeInventory fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(
          () => fake = _FakeInventory(
            InventoryState(chemicals: [_acetone]),
            failFor: failFor,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ImportScreen(
          pickFile: () async => null,
          initial: ImportSource(name: 'shelf.csv', text: csv),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('CSV parser', () {
    test('handles quotes, escaped quotes, CRLF, BOM and blank lines', () {
      final rows = parseCsv(
        '\uFEFFname,notes\r\n"Sulfuric acid","98%, ""conc."" grade"\r\n\r\n'
        'Water,"line one\nline two"\n',
      );
      expect(rows, [
        ['name', 'notes'],
        ['Sulfuric acid', '98%, "conc." grade'],
        ['Water', 'line one\nline two'],
      ]);
    });

    test('keeps empty trailing cells and detects ; and tab delimiters', () {
      expect(parseCsv('a,,b,\n'), [
        ['a', '', 'b', ''],
      ]);
      expect(detectDelimiter('name;qty;unit\n'), ';');
      expect(detectDelimiter('name\tqty\tunit\n'), '\t');
      expect(detectDelimiter('"a,b";c\n'), ';');
      expect(parseCsv('name;qty\nEthanol;5\n'), [
        ['name', 'qty'],
        ['Ethanol', '5'],
      ]);
    });
  });

  group('IMPORT-01 mapping and validation', () {
    test('auto-maps the app export headers and shared formula/category', () {
      final rows = parseCsv(_exportCsv);
      expect(looksLikeHeader(rows.first), isTrue);
      final mapping = autoMapHeaders(rows.first);
      expect(mapping[ImportField.type], 0);
      expect(mapping[ImportField.name], 1);
      expect(mapping[ImportField.formula], 2);
      expect(mapping[ImportField.category], 2);
      expect(mapping[ImportField.quantity], 3);
      expect(mapping[ImportField.unit], 4);
      expect(mapping[ImportField.threshold], 5);
      expect(mapping[ImportField.notes], 6);
      expect(mapping[ImportField.supplier], 7);
      expect(mapping[ImportField.casNumber], 8);
      expect(mapping[ImportField.concentration], 9);
      expect(mapping[ImportField.location], 10);
      expect(mapping[ImportField.expiryDate], 11);
      expect(mapping[ImportField.hazards], 12);
    });

    test('maps foreign headers loosely and spots data-only files', () {
      final mapping = autoMapHeaders(['Item Name', 'Qty', 'UOM', 'Vendor']);
      expect(mapping[ImportField.name], 0);
      expect(mapping[ImportField.quantity], 1);
      expect(mapping[ImportField.unit], 2);
      expect(mapping[ImportField.supplier], 3);
      expect(looksLikeHeader(['Ethanol', '500', 'mL']), isFalse);
    });

    test('validates rows, flags duplicates and reports per line', () {
      final table = parseCsv(_exportCsv);
      final rows = buildImportRows(
        rows: table,
        mapping: autoMapHeaders(table.first),
        target: ImportTarget.auto,
        hasHeader: true,
        existingChemicals: [_acetone],
        existingApparatus: const [],
      );
      expect(rows, hasLength(5));

      final ethanol = rows[0];
      expect(ethanol.line, 2);
      expect(ethanol.kind, ItemKind.chemical);
      expect(ethanol.hasErrors, isFalse);
      expect(ethanol.details.supplier, 'Merck');
      expect(ethanol.details.expiryDate, DateTime(2030, 1, 31));
      expect(ethanol.details.hazardClasses, ['GHS02', 'GHS07']);
      expect(ethanol.notes, '96%, food grade');

      final acetone = rows[1];
      expect(acetone.isDuplicate, isTrue);
      expect(acetone.duplicates.single.name, 'Acetone');

      final broken = rows[2];
      expect(broken.hasErrors, isTrue);
      expect(broken.issues.single.message, 'Quantity "lots" is not a number');

      final beaker = rows[3];
      expect(beaker.kind, ItemKind.apparatus);
      expect(beaker.subtitle, 'glassware');
      expect(beaker.hasErrors, isFalse);

      final hotPlate = rows[4];
      expect(hotPlate.hasErrors, isTrue);
      expect(
        hotPlate.issues.map((issue) => issue.message),
        contains('Apparatus counts must be whole numbers'),
      );

      final summary = ImportSummary.of(rows);
      expect(summary.total, 5);
      expect(summary.ready, 2);
      expect(summary.duplicates, 1);
      expect(summary.errors, 2);
    });

    test('missing type, unknown units and repeated rows are explained', () {
      final table = parseCsv(
        'name,quantity,unit\nWater,10,bucket\nwater,5,mL\n,1,mL\n',
      );
      final rows = buildImportRows(
        rows: table,
        mapping: autoMapHeaders(table.first),
        target: ImportTarget.chemicals,
        hasHeader: true,
        existingChemicals: const [],
        existingApparatus: const [],
      );
      expect(rows[0].unit, 'mL');
      expect(
        rows[0].issues.single.message,
        'Unknown unit "bucket", using mL',
      );
      expect(rows[0].hasErrors, isFalse);
      expect(
        rows[1].issues.map((issue) => issue.message),
        contains('Repeated earlier in this file'),
      );
      expect(rows[2].issues.single.message, 'Missing name');

      final typed = buildImportRows(
        rows: table,
        mapping: autoMapHeaders(table.first),
        target: ImportTarget.auto,
        hasHeader: true,
        existingChemicals: const [],
        existingApparatus: const [],
      );
      expect(
        typed.first.issues.first.message,
        'Missing type (chemical or apparatus)',
      );
    });

    test('dates accept ISO and day-first formats', () {
      expect(parseImportDate('2027-03-01'), DateTime(2027, 3, 1));
      expect(parseImportDate('01/03/2027'), DateTime(2027, 3, 1));
      expect(parseImportDate('15.03.2027'), DateTime(2027, 3, 15));
      expect(parseImportDate('03/15/2027'), DateTime(2027, 3, 15));
      expect(parseImportDate('31/02/2027'), isNull);
      expect(parseImportDate('soon'), isNull);
    });

    test('the report lists every skipped row with its line', () {
      final table = parseCsv(_exportCsv);
      final rows = buildImportRows(
        rows: table,
        mapping: autoMapHeaders(table.first),
        target: ImportTarget.auto,
        hasHeader: true,
        existingChemicals: [_acetone],
        existingApparatus: const [],
      );
      final report = buildImportReport(
        fileName: 'shelf.csv',
        imported: 2,
        problems: [(rows[2], 'Quantity "lots" is not a number')],
      );
      expect(report, contains('Imported: 2'));
      expect(report, contains('line 4: Broken row · X · 0 mL — Quantity'));
    });
  });

  group('IMPORT-01 screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('previews, skips duplicates and errors, imports the rest', (
      tester,
    ) async {
      final fake = await _pump(tester, csv: _exportCsv);
      expect(find.byKey(const Key('import-file-summary')), findsOneWidget);
      expect(find.text('shelf.csv · 5 data rows'), findsOneWidget);
      expect(find.text('Import 2 items'), findsOneWidget);
      expect(find.textContaining('matches Acetone'), findsOneWidget);
      expect(find.text('skip'), findsNWidgets(3));

      await tester.ensureVisible(find.byKey(const Key('import-submit')));
      await tester.tap(find.byKey(const Key('import-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-report')), findsOneWidget);
      expect(
        find.textContaining('2 items imported from shelf.csv'),
        findsOneWidget,
      );
      expect(fake.addedChemicals.map((entry) => entry.$1), ['Ethanol']);
      expect(fake.addedChemicals.single.$4.casNumber, '64-17-5');
      expect(fake.addedApparatus.map((entry) => entry.$1), ['Beaker 250 mL']);
      expect(find.textContaining('line 3: acetone'), findsOneWidget);
      expect(find.textContaining('line 4: Broken row'), findsOneWidget);
      expect(find.textContaining('line 6: Hot plate'), findsOneWidget);
      expect(find.byKey(const Key('import-share-report')), findsOneWidget);
    });

    testWidgets('duplicates can be imported anyway and failures are reported', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        csv: _exportCsv,
        failFor: const {'Ethanol'},
      );
      await tester.ensureVisible(find.byKey(const Key('import-duplicates')));
      await tester.tap(find.byKey(const Key('import-duplicates')));
      await tester.pumpAndSettle();
      expect(find.text('Import 3 items'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('import-submit')));
      await tester.tap(find.byKey(const Key('import-submit')));
      await tester.pumpAndSettle();
      expect(fake.addedChemicals.map((entry) => entry.$1), ['acetone']);
      expect(
        find.textContaining('2 items imported from shelf.csv · 3 not imported'),
        findsOneWidget,
      );
      expect(find.textContaining('line 2: Ethanol'), findsOneWidget);
    });

    testWidgets('columns can be remapped by hand', (tester) async {
      final fake = await _pump(
        tester,
        csv: 'Reagent,Amount,Container\nWater,250,Cabinet A\n',
      );
      // "Reagent" maps to name automatically; "Container" is not understood.
      expect(find.text('Import 1 item'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('import-map-location')),
      );
      await tester.tap(find.byKey(const Key('import-map-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Container').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('import-submit')));
      await tester.tap(find.byKey(const Key('import-submit')));
      await tester.pumpAndSettle();
      expect(fake.addedChemicals.single.$1, 'Water');
      expect(fake.addedChemicals.single.$3, 250);
      expect(fake.addedChemicals.single.$4.location, 'Cabinet A');
    });
  });
}
