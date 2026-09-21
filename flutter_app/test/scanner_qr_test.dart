import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/labels/domain/label_sheet.dart';
import 'package:lab_wizard/features/labels/domain/label_spec.dart';
import 'package:lab_wizard/features/scanner/domain/scan_batch.dart';
import 'package:lab_wizard/features/scanner/domain/scan_resolver.dart';

/// TEST-05: QR routing rules, malformed codes, apparatus labels that scan
/// back to their item, batch scanning at volume, and the structure of the
/// generated PDFs (checked from the bytes, not from the in-memory model).
Chemical _chemical(String id, String qr, {String? barcode}) => Chemical(
  id: id,
  name: 'Chemical $id',
  formula: 'X',
  unit: 'mL',
  quantity: 1,
  initialQuantity: 1,
  lowStockThreshold: 0,
  notes: '',
  qrCode: qr,
  createdAt: DateTime(2026, 1, 1),
  barcode: barcode,
);

Apparatus _apparatus(String id, {String? serial, String? barcode}) => Apparatus(
  id: id,
  name: 'Apparatus $id',
  category: 'glassware',
  quantity: 1,
  initialQuantity: 1,
  lowStockThreshold: 0,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  serialNumber: serial,
  barcode: barcode,
);

int _pageObjects(List<int> bytes) {
  // Page objects are plain dictionaries even in a compressed PDF; the
  // pages *tree* node is "/Type /Pages" and must not be counted.
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page\b(?!s)').allMatches(text).length;
}

void main() {
  final chemicals = [
    _chemical('c1', 'qr-1'),
    _chemical('c2', 'labwizard:apparatus:zzz'),
    _chemical('c3', 'qr-3', barcode: '4006381333931'),
  ];
  final apparatus = [
    _apparatus('a1', serial: 'SN-1'),
    _apparatus('a2', barcode: 'SN-BAR-2'),
  ];

  ScanMatch? resolve(String raw) =>
      resolveScan(raw, chemicals: chemicals, apparatus: apparatus);

  group('TEST-05 routing', () {
    test('prefixed and bare codes reach the right item', () {
      expect(resolve('labwizard:chemical:qr-1')!.id, 'c1');
      expect(resolve('qr-1')!.id, 'c1');
      expect(resolve('  labwizard:apparatus:a1 \n')!.id, 'a1');
      expect(resolve('labwizard:apparatus:a1')!.kind, ItemKind.apparatus);
    });

    test('an apparatus payload never falls back to a chemical', () {
      // c2 carries the literal text as its qr_code; it must not match.
      expect(resolve('labwizard:apparatus:zzz'), isNull);
    });

    test('linked barcodes match exactly and only when linked', () {
      final viaBarcode = resolve('4006381333931')!;
      expect(viaBarcode.id, 'c3');
      expect(viaBarcode.viaBarcode, isTrue);
      expect(resolve('SN-BAR-2')!.id, 'a2');
      expect(resolve('4006381333932'), isNull);
      // A Lab Wizard prefix is never treated as a barcode.
      expect(resolve('labwizard:chemical:4006381333931'), isNull);
    });

    test('malformed codes are unknown, never an error', () {
      final malformed = [
        '',
        '   ',
        '\n\t',
        'labwizard:',
        'labwizard:chemical:',
        'labwizard:apparatus:',
        'labwizard:unicorn:1',
        'LABWIZARD:CHEMICAL:qr-1',
        'labwizard:chemical:qr-1:extra',
        'qr-1\u0000',
        '🧪🧪🧪',
        'x' * 100000,
        'labwizard:apparatus:${'a' * 5000}',
      ];
      for (final code in malformed) {
        expect(() => resolve(code), returnsNormally, reason: code.length.toString());
        expect(resolve(code), isNull, reason: code.length.toString());
      }
      expect(isLabWizardCode('labwizard:'), isFalse);
      expect(isLabWizardCode('labwizard:chemical:'), isTrue);
    });
  });

  group('TEST-05 labels', () {
    test('printed labels scan back to their own item', () {
      final specs = [
        ...chemicalLabels(chemicals),
        ...apparatusLabels(apparatus),
      ];
      expect(specs, hasLength(5));
      for (final spec in specs) {
        final match = resolve(spec.data);
        expect(match, isNotNull, reason: spec.data);
        expect(match!.id, spec.id);
        expect(match.kind, spec.kind);
        expect(match.viaBarcode, isFalse);
      }
      final balance = apparatusLabels([apparatus.first]).single;
      expect(balance.data, 'labwizard:apparatus:a1');
      expect(balance.subtitle, contains('SN-1'));
      expect(chemicalLabels([_chemical('c9', '')]), isEmpty,
          reason: 'a chemical without a code has no label');
    });

    test('sheets and single labels have the expected pages', () async {
      final specs = [
        for (var index = 0; index < 41; index++)
          LabelSpec.apparatus(_apparatus('a$index', serial: 'S$index')),
      ];
      final small = await buildLabelSheet(specs).save();
      final text = latin1.decode(small, allowInvalid: true);
      expect(text, startsWith('%PDF-'));
      expect(text.trimRight(), endsWith('%%EOF'));
      expect(_pageObjects(small), 2, reason: '40 per page → 2 pages');
      // A4 portrait: 595 x 842 points.
      expect(text, contains(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+595')));

      final medium = await buildLabelSheet(
        specs,
        layout: LabelSheetLayout.medium,
      ).save();
      expect(_pageObjects(medium), 2, reason: '24 per page → 2 pages');
      final large = await buildLabelSheet(
        specs,
        layout: LabelSheetLayout.large,
      ).save();
      expect(_pageObjects(large), 4, reason: '12 per page → 4 pages');
      expect(_pageObjects(await buildSingleLabel(specs.first).save()), 1);
    });
  });

  group('TEST-05 batch scanning', () {
    test('hundreds of scans keep exact counts and unknown codes', () {
      var batch = const ScanBatch();
      final at = DateTime(2026, 9, 21, 9);
      var duplicates = 0;
      for (var index = 0; index < 300; index++) {
        final code = switch (index % 4) {
          0 => 'qr-1',
          1 => 'labwizard:apparatus:a1',
          2 => 'qr-3',
          _ => 'garbage-${index % 8}',
        };
        final (next, outcome) = batch.add(
          code,
          resolve(code),
          at: at.add(Duration(seconds: index)),
        );
        batch = next;
        if (outcome == ScanBatchOutcome.duplicate) duplicates++;
      }
      expect(batch.itemCount, 3);
      expect(batch.entries.map((entry) => entry.count), everyElement(75));
      expect(duplicates, 3 * 74);
      expect(batch.unknown.keys, hasLength(2), reason: 'garbage-3, garbage-7');
      expect(batch.unknownCount, 75);
      expect(batch.scanCount, 300);
      expect(batch.duplicateCount, 3 * 74 + (75 - 2));
      expect(batch.startedAt, at);
    });
  });
}
