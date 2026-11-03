import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import '../../shelf/presentation/item_sheet.dart';

/// Scan a reagent's QR label, or search by hand when the camera can't help.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({this.active = true, super.key});

  final bool active;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  late final MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _search = TextEditingController();
  bool _handling = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void didUpdateWidget(covariant ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _start();
    } else {
      _scanner.stop();
    }
  }

  Future<void> _start() async {
    if (!mounted || !widget.active) return;
    try {
      await _scanner.start();
    } catch (_) {
      // The scanner widget shows its own permission state.
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final query = _search.text.trim().toLowerCase();
    final results = query.isEmpty
        ? const <ItemView>[]
        : [
            ...state.chemicals.map(ItemView.fromChemical),
            ...state.apparatus.map(ItemView.fromApparatus),
          ]
              .where(
                (item) =>
                    '${item.name} ${item.subtitle}'.toLowerCase().contains(
                      query,
                    ),
              )
              .take(8)
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      children: [
        Text('Scan', style: context.aside),
        const SizedBox(height: 4),
        Text(
          'Point the camera at a label.',
          style: TextStyle(
            fontSize: 27,
            height: 1.05,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w600,
            color: lab.ink,
          ),
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: .86,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                    placeholderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .9),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton.filled(
                    tooltip: 'Torch',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _scanner.toggleTorch,
                    icon: const Icon(Icons.flashlight_on_outlined, size: 18),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      key: ValueKey(_message),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _message ?? 'Hold the label inside the frame',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text('OR SEARCH', style: context.label),
        const SizedBox(height: 6),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Name or formula',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
        ),
        ...results.map(
          (item) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: lab.card,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showItemSheet(
                  context,
                  itemId: item.id,
                  kind: item.kind,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: lab.hair),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: context.itemName),
                            Text(item.subtitle, style: context.formula),
                          ],
                        ),
                      ),
                      Text(
                        '${formatQuantity(item.quantity)} ${item.unit}',
                        style: context.figure.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _handling = true;

    final state = ref.read(inventoryProvider);
    ItemKind? kind;
    String? id;
    String? name;

    if (raw.startsWith('labwizard:apparatus:')) {
      final wanted = raw.substring('labwizard:apparatus:'.length);
      final item = state.apparatus
          .where((value) => value.id == wanted)
          .firstOrNull;
      if (item != null) {
        kind = ItemKind.apparatus;
        id = item.id;
        name = item.name;
      }
    } else {
      final code = raw.startsWith('labwizard:chemical:')
          ? raw.substring('labwizard:chemical:'.length)
          : raw;
      final item = state.chemicals
          .where((value) => value.qrCode == code)
          .firstOrNull;
      if (item != null) {
        kind = ItemKind.chemical;
        id = item.id;
        name = item.name;
      }
    }

    try {
      if (kind == null || id == null) {
        if (mounted) setState(() => _message = 'Not in your notebook');
        HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _message = null);
        return;
      }
      await _scanner.stop();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _message = 'Found $name');
      await showItemSheet(context, itemId: id, kind: kind);
    } finally {
      // Always release the latch, or one failure kills the scanner for the
      // rest of the session.
      if (mounted) {
        setState(() => _message = null);
        await _start();
      }
      _handling = false;
    }
  }
}
