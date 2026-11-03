import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/error_text.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';

/// What to buy, in the order you would walk the shelves.
///
/// The app already knows this; the only missing step was getting it out of the
/// phone and into the hands of whoever places the order. Text is the useful
/// format — it pastes straight into a message — with a PDF for printing.
String orderListText(List<ItemView> items, {DateTime? at}) {
  final when = DateFormat('d MMM yyyy').format(at ?? DateTime.now());
  final buffer = StringBuffer()
    ..writeln('Lab Wizard — order list ($when)')
    ..writeln('${items.length} item${items.length == 1 ? '' : 's'}')
    ..writeln();
  for (final item in items) {
    final level = item.threshold > 0
        ? ' — order level ${formatQuantity(item.threshold)} ${item.unit}'
        : ' — no order level set';
    buffer.writeln(
      '• ${item.name}'
      '${item.subtitle.isEmpty ? '' : ' (${item.subtitle})'}: '
      '${formatQuantity(item.quantity)} ${item.unit} left$level',
    );
  }
  buffer
    ..writeln()
    ..writeln('Sent from Lab Wizard.');
  return buffer.toString();
}

Future<Uint8List> orderListPdf(List<ItemView> items, {DateTime? at}) async {
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

/// Opens the share sheet with both formats available.
///
/// Text first, because the point of this list is to reach another person — and
/// a chat message is where it goes.
Future<void> shareOrderList(BuildContext context, List<ItemView> items) async {
  try {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.chat_outlined, size: 20),
              title: const Text('Send as a message'),
              subtitle: const Text('Pastes straight into WhatsApp'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await SharePlus.instance.share(
                  ShareParams(text: orderListText(items)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              title: const Text('Save as PDF'),
              subtitle: const Text('A4, for printing'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Printing.sharePdf(
                  bytes: await orderListPdf(items),
                  filename: 'order-list.pdf',
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
  }
}
