import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/models.dart';

/// Prints the QR labels, five across and eight down on A4.
///
/// Printers take time, so this is a screen with one button rather than a menu
/// item that silently starts a job — you can see how many labels you are about
/// to send and stop before the paper comes out.
class QrLabelScreen extends ConsumerStatefulWidget {
  const QrLabelScreen({super.key});

  @override
  ConsumerState<QrLabelScreen> createState() => _QrLabelScreenState();
}

class _QrLabelScreenState extends ConsumerState<QrLabelScreen> {
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final all = ref.watch(inventoryProvider).chemicals;
    final chemicals = all.where((item) => item.qrCode.trim().isNotEmpty).toList();
    final missing = all.length - chemicals.length;
    final pages = (chemicals.length / 40).ceil();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('QR labels'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text(
            chemicals.isEmpty
                ? 'No QR labels available'
                : '${chemicals.length} labels, $pages '
                      '${pages == 1 ? 'page' : 'pages'}',
            style: context.itemName.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            'Each label carries the reagent name, its formula, and a code the '
            'scanner reads. Print on plain A4 and cut along the lines.',
            style: context.aside.copyWith(fontSize: LabType.small),
          ),
          if (missing > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$missing chemical${missing == 1 ? '' : 's'} without a saved '
              'QR code cannot be printed.',
              style: context.aside.copyWith(fontSize: LabType.small),
            ),
          ],
          const SizedBox(height: 18),
          for (final chemical in chemicals)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Icon(Icons.qr_code_2, size: 17, color: lab.soft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      chemical.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.itemName.copyWith(fontSize: LabType.small),
                    ),
                  ),
                  Text(
                    chemical.formula,
                    style: context.formula,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: chemicals.isEmpty || _printing ? null : _print,
            icon: _printing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined, size: 18),
            label: Text(_printing ? 'Preparing…' : 'Print or save as PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final chemicals = ref.read(inventoryProvider).chemicals
          .where((item) => item.qrCode.trim().isNotEmpty)
          .toList();
      if (chemicals.isEmpty) return;
      final document = pw.Document(title: 'Lab Wizard QR labels');
      for (var offset = 0; offset < chemicals.length; offset += 40) {
        final pageItems = chemicals.skip(offset).take(40).toList();
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (_) => pw.Column(
              children: List.generate(
                8,
                (row) => pw.Expanded(
                  child: pw.Row(
                    children: List.generate(5, (column) {
                      final index = row * 5 + column;
                      return pw.Expanded(
                        child: index >= pageItems.length
                            ? pw.SizedBox()
                            : _label(pageItems[index]),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      await Printing.layoutPdf(
        name: 'Lab-Wizard-QR-Labels.pdf',
        onLayout: (_) => document.save(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  pw.Widget _label(Chemical chemical) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: .45),
    ),
    padding: const pw.EdgeInsets.all(4),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: 'labwizard:chemical:${chemical.qrCode}',
          width: 17 * PdfPageFormat.mm,
          height: 17 * PdfPageFormat.mm,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          chemical.name,
          maxLines: 2,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
        if (chemical.formula.isNotEmpty)
          pw.Text(
            chemical.formula,
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
          ),
      ],
    ),
  );
}
