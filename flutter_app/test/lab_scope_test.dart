import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/features/inventory/domain/lab_scope.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/sync/data/incremental_sync.dart';

Chemical _chemical(String id, {String? labId}) => Chemical(
  id: id,
  name: id,
  formula: '',
  unit: 'mL',
  quantity: 1,
  initialQuantity: 1,
  lowStockThreshold: 0,
  notes: '',
  qrCode: 'qr-$id',
  createdAt: DateTime(2026, 1, 1),
  labId: labId,
  organizationId: labId == null ? null : 'org-1',
);

Apparatus _apparatus(String id, {String? labId}) => Apparatus(
  id: id,
  name: id,
  category: 'other',
  quantity: 1,
  initialQuantity: 1,
  lowStockThreshold: 0,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
  labId: labId,
);

ConsumptionLog _log(String id, String itemId, {String? labId}) => ConsumptionLog(
  id: id,
  itemId: itemId,
  itemType: ItemKind.chemical,
  action: InventoryAction.consume,
  amount: 1,
  note: '',
  loggedAt: DateTime(2026, 1, 2),
  createdAt: DateTime(2026, 1, 2),
  labId: labId,
);

PendingOperation _op(String id, Map<String, dynamic> payload) => PendingOperation(
  id: id,
  userId: 'me',
  type: 'add_chemical',
  payload: payload,
  createdAt: DateTime(2026, 1, 3),
);

void main() {
  final inventory = InventoryState(
    chemicals: [
      _chemical('personal'),
      _chemical('team', labId: 'lab-a'),
      _chemical('other', labId: 'lab-b'),
    ],
    apparatus: [
      _apparatus('beaker'),
      _apparatus('shared-beaker', labId: 'lab-a'),
    ],
    logs: [
      _log('personal-log', 'personal'),
      _log('team-log', 'team'),
      // Logged before lab_id existed. It must follow the item, not the
      // empty lab id, or it would leak into Personal Lab.
      _log('legacy-team-log', 'team'),
      _log('orphan-team-log', 'missing', labId: 'lab-a'),
    ],
    outbox: [
      _op('add-personal', {'id': 'new-personal'}),
      _op('add-team', {'id': 'new-team', 'lab_id': 'lab-a'}),
      _op('use-other', {'item_id': 'other'}),
    ],
  );

  test('personal notebook hides every shared row', () {
    final scoped = scopeInventory(inventory);
    expect(scoped.chemicals.map((item) => item.id), ['personal']);
    expect(scoped.apparatus.map((item) => item.id), ['beaker']);
    expect(scoped.logs.map((log) => log.id), ['personal-log']);
    expect(scoped.outbox.map((op) => op.id), ['add-personal']);
  });

  test('a team lab shows only that lab, including a legacy log', () {
    final scoped = scopeInventory(inventory, labId: 'lab-a');
    expect(scoped.chemicals.map((item) => item.id), ['team']);
    expect(scoped.apparatus.map((item) => item.id), ['shared-beaker']);
    expect(
      scoped.logs.map((log) => log.id),
      ['team-log', 'legacy-team-log', 'orphan-team-log'],
    );
    expect(scoped.outbox.map((op) => op.id), ['add-team']);
  });

  test('a chemical map omits lab id until one is set', () {
    expect(_chemical('personal').toMap().containsKey('lab_id'), isFalse);
    expect(_chemical('team', labId: 'lab-a').toMap()['lab_id'], 'lab-a');
    expect(
      Chemical.fromMap({'id': 'x', 'lab_id': 'lab-a'}).labId,
      'lab-a',
    );
  });

  test('sync keeps a teammate shared row and drops their personal row', () {
    expect(
      syncRowVisibleTo('me', {'user_id': 'them', 'lab_id': 'lab-a'}),
      isTrue,
    );
    expect(syncRowVisibleTo('me', {'user_id': 'them'}), isFalse);
    expect(syncRowVisibleTo('me', {'user_id': 'me'}), isTrue);
  });
}
