import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../organizations/presentation/organization_providers.dart';
import 'models.dart';

/// The notebook the shelves, scanner and reports should show. The controller
/// still holds every row so a lab switch does not drop the other notebook.
final visibleInventoryProvider = Provider<InventoryState>((ref) {
  return scopeInventory(
    ref.watch(inventoryProvider),
    labId: ref.watch(activeLabProvider)?.id,
  );
});

/// Which notebook a row belongs to. A null or empty lab id is the personal
/// notebook. Shared rows never appear there, and personal rows never appear
/// in a team lab.
bool rowBelongsToLab(String? rowLabId, String? activeLabId) {
  final row = (rowLabId ?? '').trim();
  final active = (activeLabId ?? '').trim();
  if (active.isEmpty) return row.isEmpty;
  return row == active;
}

/// Shelf, reports and scanner view of [inventory] for one notebook.
///
/// Logs, loans and tasks follow their item, so an entry recorded before
/// `lab_id` was stored still stays with the bottle it changed. The outbox
/// follows the same rule, using the queued payload when the item is not in
/// the cache yet. Sync bookkeeping (last sync, errors) is kept either way.
InventoryState scopeInventory(InventoryState inventory, {String? labId}) {
  final chemicals = [
    for (final item in inventory.chemicals)
      if (rowBelongsToLab(item.labId, labId)) item,
  ];
  final apparatus = [
    for (final item in inventory.apparatus)
      if (rowBelongsToLab(item.labId, labId)) item,
  ];
  final chemicalIds = {for (final item in chemicals) item.id};
  final apparatusIds = {for (final item in apparatus) item.id};
  final knownItemIds = {
    for (final item in inventory.chemicals) item.id,
    for (final item in inventory.apparatus) item.id,
  };

  bool logInScope(ConsumptionLog log) {
    if (knownItemIds.contains(log.itemId)) {
      return chemicalIds.contains(log.itemId) ||
          apparatusIds.contains(log.itemId);
    }
    return rowBelongsToLab(log.labId, labId);
  }

  final logs = [for (final log in inventory.logs) if (logInScope(log)) log];
  final checkouts = [
    for (final checkout in inventory.checkouts)
      if (apparatusIds.contains(checkout.apparatusId)) checkout,
  ];
  final services = [
    for (final service in inventory.services)
      if (apparatusIds.contains(service.apparatusId)) service,
  ];
  final reversals = [
    for (final reversal in inventory.reversals)
      if ((reversal.itemType == ItemKind.chemical &&
              chemicalIds.contains(reversal.itemId)) ||
          (reversal.itemType == ItemKind.apparatus &&
              apparatusIds.contains(reversal.itemId)))
        reversal,
  ];
  final outbox = [
    for (final operation in inventory.outbox)
      if (_operationInScope(
        operation,
        labId,
        chemicalIds,
        apparatusIds,
        knownItemIds,
      ))
        operation,
  ];

  return InventoryState(
    chemicals: chemicals,
    apparatus: apparatus,
    logs: logs,
    outbox: outbox,
    reversals: reversals,
    checkouts: checkouts,
    services: services,
    loading: inventory.loading,
    refreshing: inventory.refreshing,
    fromCache: inventory.fromCache,
    error: inventory.error,
    lastUpdated: inventory.lastUpdated,
    lastSyncedAt: inventory.lastSyncedAt,
    syncReport: inventory.syncReport,
  );
}

bool _operationInScope(
  PendingOperation operation,
  String? labId,
  Set<String> chemicalIds,
  Set<String> apparatusIds,
  Set<String> knownItemIds,
) {
  final payloadLab = operation.payload['lab_id']?.toString();
  final itemId =
      operation.payload['item_id']?.toString() ??
      operation.payload['id']?.toString();
  if (itemId != null && knownItemIds.contains(itemId)) {
    return chemicalIds.contains(itemId) || apparatusIds.contains(itemId);
  }
  return rowBelongsToLab(payloadLab, labId);
}
