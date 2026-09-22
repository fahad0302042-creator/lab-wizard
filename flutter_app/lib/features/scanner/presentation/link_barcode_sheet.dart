import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/providers.dart';
import '../../inventory/domain/lab_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../domain/scan_resolver.dart';

/// Human name of a barcode symbology for the link sheet and history.
String barcodeFormatLabel(BarcodeFormat? format) => switch (format) {
  BarcodeFormat.qrCode => 'QR code',
  BarcodeFormat.ean13 => 'EAN-13',
  BarcodeFormat.ean8 => 'EAN-8',
  BarcodeFormat.upcA => 'UPC-A',
  BarcodeFormat.upcE => 'UPC-E',
  BarcodeFormat.code128 => 'Code 128',
  BarcodeFormat.code39 => 'Code 39',
  BarcodeFormat.code93 => 'Code 93',
  BarcodeFormat.codabar => 'Codabar',
  BarcodeFormat.itf14 => 'ITF-14',
  BarcodeFormat.dataMatrix => 'Data Matrix',
  BarcodeFormat.pdf417 => 'PDF417',
  BarcodeFormat.aztec => 'Aztec',
  _ => 'barcode',
};

/// Lets the user attach an unrecognised code to one item (SCAN-04). Resolves
/// to the linked item, or null when dismissed. Nothing is matched
/// automatically: the person picks the item, and a code can only belong to
/// one item per account (linking moves it if it was on another).
Future<ScanMatch?> showLinkBarcodeSheet(
  BuildContext context, {
  required String code,
  String formatLabel = 'barcode',
}) {
  return showModalBottomSheet<ScanMatch>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NotebookSheetFrame(
      child: LinkBarcodeForm(code: code, formatLabel: formatLabel),
    ),
  );
}

class LinkBarcodeForm extends ConsumerStatefulWidget {
  const LinkBarcodeForm({
    required this.code,
    this.formatLabel = 'barcode',
    super.key,
  });

  final String code;
  final String formatLabel;

  @override
  ConsumerState<LinkBarcodeForm> createState() => _LinkBarcodeFormState();
}

class _LinkBarcodeFormState extends ConsumerState<LinkBarcodeForm> {
  final _search = TextEditingController();
  String? _busyId;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(visibleInventoryProvider);
    final muted = context.mutedInkColor;
    final query = _search.text.trim().toLowerCase();
    final candidates = [
      for (final item in inventory.chemicals)
        _Candidate(
          match: ScanMatch.chemical(item, viaBarcode: true),
          linked: item.barcode,
          haystack: '${item.name} ${item.formula} ${item.supplier ?? ''}',
        ),
      for (final item in inventory.apparatus)
        _Candidate(
          match: ScanMatch.apparatus(item, viaBarcode: true),
          linked: item.barcode,
          haystack: '${item.name} ${item.category} ${item.serialNumber ?? ''}',
        ),
    ].where((candidate) => candidate.haystack.toLowerCase().contains(query));
    final shown = candidates.take(8).toList();
    final total = candidates.length;
    final alreadyOn = findLinkedBarcode(
      widget.code,
      chemicals: inventory.chemicals,
      apparatus: inventory.apparatus,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SketchTitle('link this code', fontSize: 30),
        Text(
          isLabWizardCode(widget.code)
              ? 'This Lab Wizard label points at an item that is not in your '
                    'notebook (deleted, or from another account).'
              : 'Lab Wizard never guesses which item a product code '
                    '(${widget.formatLabel}) belongs to. Pick the item this '
                    'code should open from now on.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 10),
        NotebookCard(
          tape: NotebookTape.blue,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.qr_code_2_outlined, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  widget.code,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.formatLabel,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (alreadyOn != null) ...[
          const SizedBox(height: 8),
          Text(
            'Currently linked to ${alreadyOn.name}. Choosing another item '
            'moves the link.',
            style: TextStyle(color: context.lowColor, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('link-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Find the chemical or apparatus…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              inventory.chemicals.isEmpty && inventory.apparatus.isEmpty
                  ? 'Your notebook is empty; add the item first.'
                  : 'Nothing matches "$query".',
              style: TextStyle(color: muted),
            ),
          ),
        for (final candidate in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NotebookCard(
              key: Key(
                'link-item-${candidate.match.kind.name}-${candidate.match.id}',
              ),
              onTap: _busyId != null ? null : () => _link(candidate),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    candidate.match.kind == ItemKind.chemical
                        ? Icons.science_outlined
                        : Icons.precision_manufacturing_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.match.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'ArchitectsDaughter',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            if (candidate.match.subtitle.isNotEmpty)
                              candidate.match.subtitle,
                            if ((candidate.linked ?? '').isNotEmpty)
                              'linked: ${candidate.linked}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_busyId == candidate.match.id)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.link),
                ],
              ),
            ),
          ),
        if (total > shown.length)
          Text(
            '${total - shown.length} more · narrow the search',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            key: const Key('link-error'),
            style: TextStyle(color: context.marginRedColor, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          key: const Key('link-not-now'),
          onPressed: _busyId != null ? null : () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Future<void> _link(_Candidate candidate) async {
    final target = candidate.match;
    final previous = candidate.linked ?? '';
    if (previous.isNotEmpty && previous != widget.code) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Replace the code on ${target.name}?'),
          content: Text(
            'It is currently linked to $previous. Only one code can be '
            'linked per item; the old one will stop opening it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('link-replace'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() {
      _busyId = target.id;
      _error = null;
    });
    final inventory = ref.read(visibleInventoryProvider);
    final notifier = ref.read(inventoryProvider.notifier);
    try {
      // A code opens exactly one item: detach it from a previous owner first.
      final owner = findLinkedBarcode(
        widget.code,
        chemicals: inventory.chemicals,
        apparatus: inventory.apparatus,
      );
      if (owner != null && owner.id != target.id) {
        await notifier.updateItem(
          type: owner.kind,
          id: owner.id,
          changes: const {barcodeColumn: null},
        );
      }
      await notifier.updateItem(
        type: target.kind,
        id: target.id,
        changes: {barcodeColumn: widget.code},
      );
      if (!mounted) return;
      Navigator.of(context).pop(target);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = friendlyErrorMessage(error);
      });
    }
  }
}

class _Candidate {
  const _Candidate({
    required this.match,
    required this.linked,
    required this.haystack,
  });

  final ScanMatch match;
  final String? linked;
  final String haystack;
}

/// Row in the item sheet showing the linked external code with *unlink*.
class LinkedBarcodeRow extends ConsumerStatefulWidget {
  const LinkedBarcodeRow({
    required this.kind,
    required this.itemId,
    required this.barcode,
    super.key,
  });

  final ItemKind kind;
  final String itemId;
  final String barcode;

  @override
  ConsumerState<LinkedBarcodeRow> createState() => _LinkedBarcodeRowState();
}

class _LinkedBarcodeRowState extends ConsumerState<LinkedBarcodeRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    return Row(
      children: [
        Icon(Icons.link, size: 18, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Linked barcode ${widget.barcode}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        TextButton(
          key: const Key('barcode-unlink'),
          onPressed: _busy ? null : _unlink,
          child: Text(_busy ? 'unlinking…' : 'unlink'),
        ),
      ],
    );
  }

  Future<void> _unlink() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .updateItem(
            type: widget.kind,
            id: widget.itemId,
            changes: const {barcodeColumn: null},
          );
      messenger.showSnackBar(const SnackBar(content: Text('Barcode unlinked')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}
