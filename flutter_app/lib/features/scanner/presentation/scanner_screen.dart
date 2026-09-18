import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_sheets.dart';

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

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScanner());
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
    _line.dispose();
    _search.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
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
      padding: const EdgeInsets.fromLTRB(54, 18, 20, 28),
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
                ColoredBox(
                  color: Colors.black,
                  child: MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                    placeholderBuilder: (_) =>
                        const Center(child: CircularProgressIndicator()),
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
                                  color: LabColors.marginRed,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: LabColors.marginRed,
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
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _scanner.toggleTorch,
                        icon: const Icon(Icons.flashlight_on_outlined),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'Switch camera',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white,
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
                    duration: const Duration(milliseconds: 220),
                    child: Container(
                      key: ValueKey(_message),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _message ?? 'Hold steady inside the frame',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
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
                            style: const TextStyle(
                              fontFamily: 'ArchitectsDaughter',
                              fontWeight: FontWeight.w700,
                            ),
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _handling = true;
    final inventory = ref.read(inventoryProvider);
    ItemKind? kind;
    String? id;
    String? name;

    if (raw.startsWith('labwizard:apparatus:')) {
      final apparatusId = raw.substring('labwizard:apparatus:'.length);
      final item = inventory.apparatus
          .where((value) => value.id == apparatusId)
          .firstOrNull;
      if (item != null) {
        kind = ItemKind.apparatus;
        id = item.id;
        name = item.name;
      }
    } else {
      final qrCode = raw.startsWith('labwizard:chemical:')
          ? raw.substring('labwizard:chemical:'.length)
          : raw;
      final item = inventory.chemicals
          .where((value) => value.qrCode == qrCode)
          .firstOrNull;
      if (item != null) {
        kind = ItemKind.chemical;
        id = item.id;
        name = item.name;
      }
    }

    if (kind == null || id == null) {
      setState(() => _message = 'This code is not in your lab notebook');
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _message = null);
      _handling = false;
      return;
    }
    await _scanner.stop();
    HapticFeedback.mediumImpact();
    if (mounted) {
      setState(() => _message = 'Found $name');
      await showItemDetailSheet(context, ref, kind, id);
    }
    if (mounted) {
      setState(() => _message = null);
      await _scanner.start();
    }
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
