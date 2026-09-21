import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/core/utils/csv.dart';
import 'package:lab_wizard/features/import/domain/csv_parser.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/reports/domain/csv_exports.dart';
import 'package:lab_wizard/features/reports/domain/report_range.dart';

void main() {
  group('csvCell', () {
    test('neutralises formula-looking text', () {
      expect(csvCell('=HYPERLINK("http://x")'), '"\'=HYPERLINK(""http://x"")"');
      expect(csvCell('+1234'), '"\'+1234"');
      expect(csvCell('-2+3+cmd|\' /C calc\'!A0'), '"\'-2+3+cmd|\' /C calc\'!A0"');
      expect(csvCell('@SUM(A1)'), '"\'@SUM(A1)"');
      expect(csvCell('\tabc'), '"\'\tabc"');
      expect(csvCell('\rabc'), '"\'\rabc"');
    });

    test('quotes only when needed and keeps numbers numeric', () {
      expect(csvCell('Acetone'), 'Acetone');
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell('two\nlines'), '"two\nlines"');
      expect(csvCell(' padded '), '" padded "');
      expect(csvCell(12), '12');
      expect(csvCell(12.5), '12.5');
      expect(csvCell(-3), '-3');
      expect(csvCell(3.0), '3');
      expect(csvCell(double.nan), '');
      expect(csvCell(null), '');
      expect(csvCell(''), '');
      expect(csvCell('a;b', delimiter: ';'), '"a;b"');
      expect(csvCell(DateTime.utc(2026, 9, 21)), '2026-09-21T00:00:00.000Z');
    });

    test('documents use CRLF and a byte-order mark', () {
      final csv = csvDocument(
        ['name', 'qty'],
        [
          ['Acetone', 5],
          ['=evil', 1],
        ],
      );
      expect(csv, '\uFEFFname,qty\r\nAcetone,5\r\n"\'=evil",1\r\n');
      expect(csvBytes(csv).take(3), [0xEF, 0xBB, 0xBF]);
      expect(csvDocument(['a'], [], byteOrderMark: false), 'a\r\n');
      // The import parser reads it back, guard removed.
      final rows = parseCsv(csv);
      expect(rows, [
        ['name', 'qty'],
        ['Acetone', '5'],
        ["'=evil", '1'],
      ]);
      expect(csvUnguard(rows.last.first), '=evil');
      expect(csvUnguard("'quoted"), "'quoted");
      expect(csvUnguard("'"), "'");
    });
  });

  group('report exports', () {
    final today = DateTime(2026, 9, 21, 12);
    final acetone = Chemical(
      id: 'c1',
      name: 'Acetone',
      formula: 'C3H6O',
      unit: 'mL',
      quantity: 40,
      initialQuantity: 100,
      lowStockThreshold: 10,
      notes: '=cmd|\' /C calc\'!A0',
      qrCode: 'qr-1',
      createdAt: DateTime(2026, 1, 2, 9),
      supplier: 'Merck, Darmstadt',
      casNumber: '67-64-1',
      hazardClasses: const ['GHS02', 'GHS07'],
      expiryDate: DateTime(2027, 1, 31),
      barcode: '4006381333931',
    );
    final beaker = Apparatus(
      id: 'a1',
      name: 'beaker 250',
      category: 'glassware',
      quantity: 0,
      initialQuantity: 6,
      lowStockThreshold: 1,
      notes: '',
      createdAt: DateTime(2026, 1, 2),
      serialNumber: '-SN-1',
    );

    test('activity export filters by range and kind, oldest first', () {
      ConsumptionLog log(String id, DateTime at, {ItemKind kind = ItemKind.chemical, String note = ''}) =>
          ConsumptionLog(
            id: id,
            itemId: kind == ItemKind.chemical ? 'c1' : 'a1',
            itemType: kind,
            action: InventoryAction.consume,
            amount: 2.5,
            note: note,
            loggedAt: at,
            createdAt: at,
          );
      final csv = activityCsv(
        range: ReportRange.lastDays(7, today: today),
        kind: ItemKind.chemical,
        logs: [
          log('l2', DateTime(2026, 9, 20, 8, 5), note: '+later'),
          log('l1', DateTime(2026, 9, 15, 0, 0), note: 'first, early'),
          log('l0', DateTime(2026, 9, 14, 23, 59)),
          log('a', DateTime(2026, 9, 18), kind: ItemKind.apparatus),
        ],
        nameOf: (_) => 'Acetone',
        detailOf: (_) => 'C3H6O',
        unitOf: (_) => 'mL',
      );
      final rows = parseCsv(csv);
      expect(rows.first, [
        'date',
        'time',
        'item',
        'formula',
        'action',
        'amount',
        'unit',
        'note',
        'entry id',
        'logged at (UTC)',
      ]);
      expect(rows, hasLength(3));
      expect(rows[1].sublist(0, 8), [
        '2026-09-15',
        '00:00',
        'Acetone',
        'C3H6O',
        'consume',
        '2.5',
        'mL',
        'first, early',
      ]);
      expect(rows[2][7], "'+later");
      expect(rows[2][8], 'l2');
      expect(rows[2][9], DateTime(2026, 9, 20, 8, 5).toUtc().toIso8601String());
    });

    test('inventory exports carry the metadata and stay formula-safe', () {
      final chemicals = parseCsv(chemicalsCsv([acetone]));
      expect(chemicals.first.length, 17);
      final row = Map.fromIterables(chemicals.first, chemicals[1]);
      expect(row['name'], 'Acetone');
      expect(row['quantity'], '40');
      expect(row['stock'], 'healthy');
      expect(row['supplier'], 'Merck, Darmstadt');
      expect(row['cas number'], '67-64-1');
      expect(row['expiry date'], '2027-01-31');
      expect(row['hazards'], 'GHS02;GHS07');
      expect(row['barcode'], '4006381333931');
      expect(row['notes'], "'=cmd|' /C calc'!A0");
      expect(row['added'], '2026-01-02');
      expect(chemicalsCsv([acetone]), isNot(contains(',=cmd')));

      final apparatus = parseCsv(apparatusCsv([beaker]));
      final gear = Map.fromIterables(apparatus.first, apparatus[1]);
      expect(gear['name'], 'beaker 250');
      expect(gear['unit'], 'pcs');
      expect(gear['stock'], 'empty');
      expect(gear['serial number'], "'-SN-1");
      expect(gear['purchase date'], '');
    });
  });
}
