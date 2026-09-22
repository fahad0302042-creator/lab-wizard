import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/utils/csv.dart';
import '../../inventory/domain/models.dart';
import '../../reports/domain/csv_exports.dart';
import '../../reports/domain/report_range.dart';

/// Writes every table of [state] to CSV files and opens the share sheet
/// (ACCOUNT-03 "export first"). Returns the file names.
Future<List<String>> shareFullExport(InventoryState state) async {
  final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final everything = ReportRange.custom(DateTime(2000), DateTime.now());
  String nameOf(ItemKind kind, String id) => kind == ItemKind.chemical
      ? state.chemicals
                .where((item) => item.id == id)
                .map((c) => c.name)
                .firstOrNull ??
            'Removed chemical'
      : state.apparatus
                .where((item) => item.id == id)
                .map((a) => a.name)
                .firstOrNull ??
            'Removed apparatus';
  String detailOf(ItemKind kind, String id) => kind == ItemKind.chemical
      ? state.chemicals
                .where((item) => item.id == id)
                .map((c) => c.formula)
                .firstOrNull ??
            ''
      : state.apparatus
                .where((item) => item.id == id)
                .map((a) => a.category)
                .firstOrNull ??
            '';
  String unitOf(String id) =>
      state.chemicals
          .where((item) => item.id == id)
          .map((c) => c.unit)
          .firstOrNull ??
      '';

  final files = <String, String>{
    'lab-wizard-chemicals-$stamp.csv': chemicalsCsv(state.chemicals),
    'lab-wizard-apparatus-$stamp.csv': apparatusCsv(state.apparatus),
    'lab-wizard-chemical-activity-$stamp.csv': activityCsv(
      range: everything,
      kind: ItemKind.chemical,
      logs: state.logs,
      nameOf: (id) => nameOf(ItemKind.chemical, id),
      detailOf: (id) => detailOf(ItemKind.chemical, id),
      unitOf: unitOf,
    ),
    'lab-wizard-apparatus-activity-$stamp.csv': activityCsv(
      range: everything,
      kind: ItemKind.apparatus,
      logs: state.logs,
      nameOf: (id) => nameOf(ItemKind.apparatus, id),
      detailOf: (id) => detailOf(ItemKind.apparatus, id),
      unitOf: (_) => 'pcs',
    ),
  };
  final directory = await getTemporaryDirectory();
  final shared = <XFile>[];
  for (final entry in files.entries) {
    final file = File('${directory.path}/${entry.key}');
    await file.writeAsBytes(csvBytes(entry.value), flush: true);
    shared.add(XFile(file.path, mimeType: 'text/csv', name: entry.key));
  }
  await SharePlus.instance.share(
    ShareParams(
      title: 'Lab Wizard data export',
      text: 'Lab Wizard data export ($stamp)',
      files: shared,
    ),
  );
  return files.keys.toList();
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
