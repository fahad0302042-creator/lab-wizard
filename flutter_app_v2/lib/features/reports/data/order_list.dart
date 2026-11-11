import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import '../presentation/order_plan_screen.dart';

class OrderPlanEntry {
  const OrderPlanEntry({this.amount, this.note = ''});
  final double? amount;
  final String note;
}

/// What to buy, in the order you would walk the shelves.
///
/// The app already knows this; the only missing step was getting it out of the
/// phone and into the hands of whoever places the order. Text is the useful
/// format — it pastes straight into a message — with a PDF for printing.
String orderListText(
  List<ItemView> items, {
  DateTime? at,
  Map<String, OrderPlanEntry> plan = const {},
}) {
  final when = DateFormat('d MMM yyyy').format(at ?? DateTime.now());
  final buffer = StringBuffer()
    ..writeln('Lab Wizard — order list ($when)')
    ..writeln('${items.length} item${items.length == 1 ? '' : 's'}')
    ..writeln();
  for (final item in items) {
    final level = item.threshold > 0
        ? ' — order level ${formatQuantity(item.threshold)} ${item.unit}'
        : ' — no order level set';
    final entry = plan[item.id];
    buffer.writeln(
      '• ${item.name}'
      '${item.subtitle.isEmpty ? '' : ' (${item.subtitle})'}: '
      '${formatQuantity(item.quantity)} ${item.unit} left$level',
    );
    if (entry?.amount != null) {
      buffer.writeln('  Order: ${formatQuantity(entry!.amount!)} ${item.unit}');
    }
    if (entry?.note.isNotEmpty == true) {
      buffer.writeln('  Note: ${entry!.note}');
    }
  }
  buffer
    ..writeln()
    ..writeln('Sent from Lab Wizard.');
  return buffer.toString();
}

Future<Uint8List> orderListPdf(
  List<ItemView> items, {
  DateTime? at,
  Map<String, OrderPlanEntry> plan = const {},
}) async {
  final when = at ?? DateTime.now();
  final document = pw.Document(title: 'Lab Wizard order list');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      build: (_) => [
        pw.Text(
          'Lab Wizard — order list',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          '${DateFormat('d MMMM yyyy').format(when)} · '
          '${items.length} item${items.length == 1 ? '' : 's'}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Item',
            'Formula / category',
            'On shelf',
            'Order level',
            'To order / note',
          ],
          data: items
              .map(
                (item) => [
                  item.name,
                  item.subtitle,
                  '${formatQuantity(item.quantity)} ${item.unit}',
                  item.threshold > 0
                      ? '${formatQuantity(item.threshold)} ${item.unit}'
                      : '—',
                  [
                    if (plan[item.id]?.amount != null)
                      '${formatQuantity(plan[item.id]!.amount!)} ${item.unit}',
                    if (plan[item.id]?.note.isNotEmpty == true)
                      plan[item.id]!.note,
                  ].join('\n'),
                ],
              )
              .toList(),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          border: null,
        ),
      ],
    ),
  );
  return document.save();
}

/// Open an editable plan before sharing; nothing changes on the shelf.
Future<void> shareOrderList(BuildContext context, List<ItemView> items) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => OrderPlanScreen(items: items),
  ));
}
