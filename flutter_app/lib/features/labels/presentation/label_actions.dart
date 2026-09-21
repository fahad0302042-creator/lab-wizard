import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../domain/label_sheet.dart';
import '../domain/label_spec.dart';
import 'label_image.dart';

/// What to do with a sheet of labels.
enum LabelSheetAction { print, share }

class LabelSheetChoice {
  const LabelSheetChoice({required this.layout, required this.action});

  final LabelSheetLayout layout;
  final LabelSheetAction action;
}

/// Lets the user pick the grid (40/24/12 per A4) and whether to print or
/// share the PDF. Returns null when dismissed.
Future<LabelSheetChoice?> showLabelSheetDialog(
  BuildContext context, {
  required int count,
  LabelSheetLayout initialLayout = LabelSheetLayout.small,
}) {
  return showDialog<LabelSheetChoice>(
    context: context,
    builder: (context) =>
        _LabelSheetDialog(count: count, initial: initialLayout),
  );
}

class _LabelSheetDialog extends StatefulWidget {
  const _LabelSheetDialog({required this.count, required this.initial});

  final int count;
  final LabelSheetLayout initial;

  @override
  State<_LabelSheetDialog> createState() => _LabelSheetDialogState();
}

class _LabelSheetDialogState extends State<_LabelSheetDialog> {
  late LabelSheetLayout _layout = widget.initial;

  @override
  Widget build(BuildContext context) {
    final pages = labelPageCount(widget.count, _layout);
    return AlertDialog(
      title: Text(
        '${widget.count} QR label${widget.count == 1 ? '' : 's'} on A4',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<LabelSheetLayout>(
              groupValue: _layout,
              onChanged: (value) {
                if (value != null) setState(() => _layout = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final layout in LabelSheetLayout.values)
                    RadioListTile<LabelSheetLayout>(
                      key: Key('label-layout-${layout.name}'),
                      value: layout,
                      contentPadding: EdgeInsets.zero,
                      title: Text(layout.title),
                      subtitle: Text(layout.hint),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$pages page${pages == 1 ? '' : 's'} · labels are filled row by '
              'row, so a partly used sheet can be printed again later.',
              style: TextStyle(color: context.mutedInkColor, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          key: const Key('label-sheet-share'),
          onPressed: () => Navigator.pop(
            context,
            LabelSheetChoice(layout: _layout, action: LabelSheetAction.share),
          ),
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Share PDF'),
        ),
        FilledButton.icon(
          key: const Key('label-sheet-print'),
          onPressed: () => Navigator.pop(
            context,
            LabelSheetChoice(layout: _layout, action: LabelSheetAction.print),
          ),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print'),
        ),
      ],
    );
  }
}

/// Asks for a layout, then prints or shares an A4 sheet with [labels]
/// (QR-01/QR-02). Returns true when something was handed to the system.
Future<bool> printLabelSheet(
  BuildContext context,
  List<LabelSpec> labels, {
  LabelSheetLayout initialLayout = LabelSheetLayout.small,
}) async {
  if (labels.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to print: no items with a code.')),
    );
    return false;
  }
  final choice = await showLabelSheetDialog(
    context,
    count: labels.length,
    initialLayout: initialLayout,
  );
  if (choice == null || !context.mounted) return false;
  try {
    final document = buildLabelSheet(labels, layout: choice.layout);
    final stem = labels.length == 1
        ? labels.single.fileStem
        : '${labels.length}-${labels.first.kind.name}-labels';
    switch (choice.action) {
      case LabelSheetAction.print:
        await Printing.layoutPdf(
          name: 'lab-wizard-$stem.pdf',
          onLayout: (_) => document.save(),
        );
      case LabelSheetAction.share:
        await Printing.sharePdf(
          bytes: await document.save(),
          filename: 'lab-wizard-$stem.pdf',
        );
    }
    return true;
  } catch (error) {
    if (context.mounted) _showError(context, error);
    return false;
  }
}

/// Shares a single label as a PNG through the system share sheet (QR-03).
Future<void> shareLabelImage(BuildContext context, LabelSpec label) async {
  try {
    final bytes = await renderLabelPng(label);
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/lab-wizard-label-${label.fileStem}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    HapticFeedback.selectionClick();
    await SharePlus.instance.share(
      ShareParams(
        title: '${label.title} QR label',
        files: [XFile(file.path, mimeType: 'image/png')],
      ),
    );
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

/// Shares a single label as a small PDF page (QR-03).
Future<void> shareLabelPdf(BuildContext context, LabelSpec label) async {
  try {
    await Printing.sharePdf(
      bytes: await buildSingleLabel(label).save(),
      filename: 'lab-wizard-label-${label.fileStem}.pdf',
    );
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

/// Prints a single label page (QR-03).
Future<void> printLabel(BuildContext context, LabelSpec label) async {
  try {
    await Printing.layoutPdf(
      name: 'lab-wizard-label-${label.fileStem}.pdf',
      onLayout: (_) => buildSingleLabel(label).save(),
    );
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Could not export: ${friendlyErrorMessage(error)}')),
  );
}

/// Preview plus *share image* / *PDF* / *print* buttons for one item's
/// label, shown in the item sheet (QR-03).
class LabelCard extends StatelessWidget {
  const LabelCard({super.key, required this.label});

  final LabelSpec label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: NotebookCard(
            tape: NotebookTape.yellow,
            padding: const EdgeInsets.all(10),
            child: LayoutBuilder(
              builder: (context, constraints) => LabelPreview(
                label,
                width: constraints.maxWidth.isFinite
                    ? constraints.maxWidth.clamp(200.0, 340.0).toDouble()
                    : 300,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            TextButton.icon(
              key: const Key('label-share-image'),
              onPressed: () => shareLabelImage(context, label),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('share image'),
            ),
            TextButton.icon(
              key: const Key('label-share-pdf'),
              onPressed: () => shareLabelPdf(context, label),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
            TextButton.icon(
              key: const Key('label-print'),
              onPressed: () => printLabel(context, label),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('print'),
            ),
          ],
        ),
      ],
    );
  }
}
