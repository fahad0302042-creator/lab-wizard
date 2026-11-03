import '../../../core/widgets/jar_metrics.dart';
import 'models.dart';

/// One item on either shelf, flattened so a single row widget can render
/// chemicals and apparatus without caring which is which.
///
/// The two tables have the same shape apart from `formula` versus `category`,
/// so unifying them here removes the duplicated sort/filter/swipe code that the
/// old app carried twice.
class ItemView {
  const ItemView({
    required this.id,
    required this.kind,
    required this.name,
    required this.subtitle,
    required this.notes,
    required this.unit,
    required this.quantity,
    required this.initialQuantity,
    required this.threshold,
    this.qrCode = '',
  });

  factory ItemView.fromChemical(Chemical item) => ItemView(
    id: item.id,
    kind: ItemKind.chemical,
    name: item.name,
    subtitle: item.formula.isEmpty ? 'no formula noted' : item.formula,
    notes: item.notes,
    unit: item.unit,
    quantity: item.quantity,
    initialQuantity: item.initialQuantity,
    threshold: item.lowStockThreshold,
    qrCode: item.qrCode,
  );

  factory ItemView.fromApparatus(Apparatus item) => ItemView(
    id: item.id,
    kind: ItemKind.apparatus,
    name: item.name,
    subtitle: item.category,
    notes: item.notes,
    unit: 'pcs',
    quantity: item.quantity,
    initialQuantity: item.initialQuantity,
    threshold: item.lowStockThreshold,
  );

  final String id;
  final ItemKind kind;
  final String name;
  final String subtitle;
  final String notes;
  final String unit;
  final double quantity;
  final double initialQuantity;
  final double threshold;
  final String qrCode;

  bool get isChemical => kind == ItemKind.chemical;

  /// Apparatus is counted in whole pieces, so its jar ticks one unit at a time
  /// rather than showing a rounded percentage.
  bool get piecewise => kind == ItemKind.apparatus;

  /// What logging use is called for this kind. Breaking a beaker isn't "use".
  String get useLabel => isChemical ? 'use' : 'damage';

  JarMetrics get metrics => jarMetrics(
    quantity: quantity,
    initialQuantity: initialQuantity,
    threshold: threshold,
    piecewise: piecewise,
  );
}
