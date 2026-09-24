import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../inventory/domain/lab_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../domain/recent_scan.dart';
import '../domain/scan_batch.dart';
import '../domain/scan_resolver.dart';
import '../scanner_providers.dart';
import 'batch_summary_sheet.dart';
import 'link_barcode_sheet.dart';
import 'recent_scans_section.dart';
import 'scan_action_sheet.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({this.active = true, super.key});

  final bool active;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _scanner;
  late final AnimationController _line;
  final _search = TextEditingController();
  bool _handling = false;
  String? _message;
  Timer? _messageTimer;
  bool _batchMode = false;
  ScanBatch _batch = const ScanBatch();
  String? _lastRaw;
  DateTime? _lastRawAt;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      autoStart: false,
      // Product formats are decoded too, but only acted on when the
      // "product barcodes" preference is on (SCAN-04).
      formats: const [
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf14,
      ],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScanner());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sweeping line is decoration; it stays still (and costs no frames)
    // when the system asks for reduced motion (A11Y-05).
    if (MediaQuery.disableAnimationsOf(context)) {
      _line.stop();
    } else if (!_line.isAnimating) {
      _line.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _startScanner();
    } else {
      _scanner.stop();
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || !widget.active) return;
    try {
      await _scanner.start();
    } catch (_) {
      // The camera widget presents its own permission/error state.
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _line.dispose();
    _search.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(visibleInventoryProvider);
    final query = _search.text.trim().toLowerCase();
    final results = query.isEmpty
        ? const <_ScanSearchResult>[]
        : [
                ...inventory.chemicals.map(
                  (item) => _ScanSearchResult(
                    kind: ItemKind.chemical,
                    id: item.id,
                    name: item.name,
                    subtitle: item.formula,
                    quantity: item.quantity,
                    unit: item.unit,
                  ),
                ),
                ...inventory.apparatus.map(
                  (item) => _ScanSearchResult(
                    kind: ItemKind.apparatus,
                    id: item.id,
                    name: item.name,
                    subtitle: item.category,
                    quantity: item.quantity,
                    unit: 'pcs',
                  ),
                ),
              ]
              .where(
                (item) => '${item.name} ${item.subtitle}'
                    .toLowerCase()
                    .contains(query),
              )
              .take(8)
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(notebookGutter, 20, 18, 28),
      children: [
        const PageHeading('scan an item'),
        Text(
          'Point the camera at a Lab Wizard chemical or apparatus label.',
          style: TextStyle(color: context.mutedInkColor),
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: .82,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  label:
                      'Camera viewfinder. Hold the phone over a Lab Wizard '
                      'label; the result is announced.',
                  excludeSemantics: true,
                  child: ColoredBox(
                    color: Colors.black,
                    child: MobileScanner(
                      controller: _scanner,
                      onDetect: _onDetect,
                      placeholderBuilder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
                const _ScannerShade(),
                Center(
                  child: SizedBox.square(
                    dimension: 238,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: _ScanCornersPainter()),
                        ),
                        if (!MediaQuery.disableAnimationsOf(context))
                          AnimatedBuilder(
                            animation: _line,
                            builder: (_, _) => Positioned(
                              left: 12,
                              right: 12,
                              top: 18 + _line.value * 196,
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  color: LabColors.marginRedDark,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: LabColors.marginRedDark,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    children: [
                      IconButton.filled(
                        tooltip: 'Torch',
                        style: IconButton.styleFrom(
                          backgroundColor: context.cardColor,
                          foregroundColor: context.inkColor,
                          side: BorderSide(color: context.inkColor, width: 1.4),
                        ),
                        onPressed: _scanner.toggleTorch,
                        icon: const Icon(Icons.flashlight_on_outlined),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'Switch camera',
                        style: IconButton.styleFrom(
                          backgroundColor: context.cardColor,
                          foregroundColor: context.inkColor,
                          side: BorderSide(color: context.inkColor, width: 1.4),
                        ),
                        onPressed: _scanner.switchCamera,
                        icon: const Icon(Icons.cameraswitch_outlined),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: AnimatedSwitcher(
                    duration: context.motion(const Duration(milliseconds: 220)),
                    child: Container(
                      key: ValueKey(_message),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.inkColor, width: 1.3),
                      ),
                      // Live region: TalkBack speaks each new status
                      // ("Found Acetone", "not in your lab notebook").
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _message ?? _idleMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.inkColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                key: const Key('scan-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.qr_code_scanner),
                    label: Text('Single'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.playlist_add_check_outlined),
                    label: Text('Batch'),
                  ),
                ],
                selected: {_batchMode},
                onSelectionChanged: (selection) =>
                    setState(() => _batchMode = selection.first),
              ),
            ),
            if (_batch.isNotEmpty) ...[
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                key: const Key('batch-finish'),
                onPressed: _finishBatch,
                icon: const Icon(Icons.checklist_outlined),
                label: Text('Finish (${_batch.itemCount})'),
              ),
            ],
          ],
        ),
        if (_batchMode) ...[
          const SizedBox(height: 6),
          Text(
            _batch.isEmpty
                ? 'Every recognised label is added to a list without '
                      'leaving the camera; repeated labels are counted, '
                      'not listed twice.'
                : _batch.summaryLine,
            style: TextStyle(color: context.mutedInkColor, fontSize: 12),
          ),
        ],
        SwitchListTile.adaptive(
          key: const Key('scan-product-barcodes'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Also read product barcodes'),
          subtitle: Text(
            'EAN, UPC, Code 128 and similar open only the item you linked '
            'them to; nothing is matched by guesswork.',
            style: TextStyle(color: context.mutedInkColor, fontSize: 12),
          ),
          value: ref.watch(productBarcodesProvider),
          onChanged: (value) =>
              ref.read(productBarcodesProvider.notifier).set(value),
        ),
        const SizedBox(height: 16),
        const RecentScansSection(),
        const PageHeading('or search manually', trailing: SizedBox.shrink()),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Chemical, formula, or apparatus…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...results.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NotebookCard(
                onTap: () =>
                    showItemDetailSheet(context, ref, item.kind, item.id),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(
                      item.kind == ItemKind.chemical
                          ? Icons.science_outlined
                          : Icons.precision_manufacturing_outlined,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (item.subtitle.isNotEmpty)
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                color: context.mutedInkColor,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text('${formatQuantity(item.quantity)} ${item.unit}'),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String get _idleMessage {
    if (!_batchMode) return 'Hold steady inside the frame';
    if (_batch.isEmpty) return 'Batch mode · scan the first label';
    return '${_batch.summaryLine} · next label';
  }

  void _flash(
    String text, {
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    setState(() => _message = text);
    _messageTimer?.cancel();
    _messageTimer = Timer(duration, () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _finishBatch() async {
    if (_batch.isEmpty) return;
    await _scanner.stop();
    if (!mounted) return;
    final done = await showBatchSummarySheet(context, _batch);
    if (!mounted) return;
    if (done) setState(() => _batch = const ScanBatch());
    if (widget.active) await _scanner.start();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (barcode == null || raw == null || raw.isEmpty) return;
    final format = barcode.format;
    final isProductCode =
        format != BarcodeFormat.qrCode && format != BarcodeFormat.unknown;
    if (isProductCode && !ref.read(productBarcodesProvider)) return;
    final now = DateTime.now();
    // The camera can re-read a label that stays in view; treat repeats within
    // a couple of seconds as the same read.
    if (raw == _lastRaw &&
        _lastRawAt != null &&
        now.difference(_lastRawAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastRaw = raw;
    _lastRawAt = now;
    _handling = true;
    final inventory = ref.read(visibleInventoryProvider);
    final match = resolveScan(
      raw,
      chemicals: inventory.chemicals,
      apparatus: inventory.apparatus,
    );
    final history = ref.read(recentScansProvider.notifier);

    if (_batchMode) {
      final (batch, outcome) = _batch.add(raw, match, at: now);
      unawaited(
        history.record(
          match == null
              ? RecentScan.unknown(raw.trim(), now)
              : RecentScan.found(match, raw.trim(), now),
        ),
      );
      _batch = batch;
      switch (outcome) {
        case ScanBatchOutcome.added:
          HapticFeedback.mediumImpact();
          _flash('Added ${match!.name}');
        case ScanBatchOutcome.duplicate:
          HapticFeedback.lightImpact();
          final item = match!;
          final count = batch.entries
              .firstWhere(
                (entry) => entry.key == '${item.kind.name}:${item.id}',
              )
              .count;
          _flash('${item.name} already in batch (×$count)');
        case ScanBatchOutcome.unknown:
          HapticFeedback.heavyImpact();
          _flash('Not in your notebook · kept in the summary');
      }
      _handling = false;
      return;
    }

    await _scanner.stop();
    if (!mounted) return;
    var found = match;
    if (found == null) {
      // SCAN-04: nothing carries this code. Offer an explicit link instead of
      // guessing; the person can also just dismiss the sheet.
      unawaited(history.record(RecentScan.unknown(raw.trim(), now)));
      HapticFeedback.heavyImpact();
      setState(() => _message = 'This code is not in your lab notebook');
      found = await showLinkBarcodeSheet(
        context,
        code: raw.trim(),
        formatLabel: barcodeFormatLabel(format),
      );
      if (!mounted) return;
    } else {
      HapticFeedback.mediumImpact();
    }
    if (found != null) {
      final item = found;
      unawaited(
        history.record(RecentScan.found(item, raw.trim(), DateTime.now())),
      );
      setState(() => _message = 'Found ${item.name}');
      // SCAN-03: quick amount + action first; the full sheet is one tap away.
      final result = await showScanActionSheet(
        context,
        kind: item.kind,
        itemId: item.id,
      );
      if (!mounted) return;
      if (result?.openDetails ?? false) {
        await showItemDetailSheet(context, ref, item.kind, item.id);
        if (!mounted) return;
      }
      final outcome = result?.message;
      if (outcome != null) {
        _flash(outcome, duration: const Duration(seconds: 3));
      } else {
        setState(() => _message = null);
      }
    } else {
      setState(() => _message = null);
    }
    if (widget.active) await _scanner.start();
    _handling = false;
  }
}

class _ScannerShade extends StatelessWidget {
  const _ScannerShade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _ScannerShadePainter()));
  }
}

class _ScannerShadePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 250,
      height: 250,
    );
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .42));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanCornersPainter extends CustomPainter {
  const _ScanCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const length = 34.0;
    final paths = [
      Path()
        ..moveTo(0, length)
        ..lineTo(0, 0)
        ..lineTo(length, 0),
      Path()
        ..moveTo(size.width - length, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, length),
      Path()
        ..moveTo(size.width, size.height - length)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width - length, size.height),
      Path()
        ..moveTo(length, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, size.height - length),
    ];
    for (final path in paths) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanSearchResult {
  const _ScanSearchResult({
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
    required this.quantity,
    required this.unit,
  });

  final ItemKind kind;
  final String id;
  final String name;
  final String subtitle;
  final double quantity;
  final String unit;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
