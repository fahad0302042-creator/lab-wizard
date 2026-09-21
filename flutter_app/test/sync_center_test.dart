import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final discarded = <String>[];
  final retried = <String>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> retryOperation(String operationId) async {
    retried.add(operationId);
  }

  @override
  Future<void> retryAll() async {
    retried.add('all');
  }

  @override
  Future<void> discardOperation(String operationId) async {
    discarded.add(operationId);
    state = state.copyWith(
      outbox: state.outbox
          .where((operation) => operation.id != operationId)
          .toList(),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SYNC-01: sync center lists, retries and discards changes', (
    tester,
  ) async {
    final now = DateTime.now();
    final seed = InventoryState(
      lastSyncedAt: now.subtract(const Duration(minutes: 10)),
      outbox: [
        PendingOperation(
          id: 'op-add',
          userId: 'u1',
          type: 'add_chemical',
          payload: const {'id': 'c1', 'name': 'Acetone'},
          createdAt: now.subtract(const Duration(minutes: 8)),
          label: 'Add chemical Acetone',
        ),
        PendingOperation(
          id: 'op-consume',
          userId: 'u1',
          type: 'inventory_action',
          payload: const {'item_id': 'c2', 'action': 'consume', 'amount': 5},
          createdAt: now.subtract(const Duration(minutes: 6)),
          attempts: 3,
          lastError: 'PostgrestException: Insufficient stock: only 2 available',
          status: PendingStatus.failed,
          lastAttemptAt: now.subtract(const Duration(minutes: 1)),
          label: 'Consume 5 mL of Ethanol',
        ),
      ],
    );
    late _FakeInventory fake;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryProvider.overrideWith(() => fake = _FakeInventory(seed)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SyncCenterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add chemical Acetone'), findsOneWidget);
    expect(find.text('Consume 5 mL of Ethanol'), findsOneWidget);
    expect(find.text('waiting'), findsOneWidget);
    expect(find.text('needs attention'), findsOneWidget);
    expect(find.text('1 needs attention'), findsOneWidget);
    expect(find.textContaining('less stock'), findsOneWidget);
    expect(find.textContaining('3 attempts'), findsOneWidget);
    expect(
      find.textContaining('Last successful sync: 10 min ago'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sync-retry-all')), findsOneWidget);

    await tester.tap(find.text('retry now').first);
    await tester.pumpAndSettle();
    expect(fake.retried, ['op-add']);

    await tester.tap(find.byKey(const Key('sync-retry-all')));
    await tester.pumpAndSettle();
    expect(fake.retried, ['op-add', 'all']);

    await tester.tap(find.text('discard').last);
    await tester.pumpAndSettle();
    expect(find.text('Discard this change?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(fake.discarded, ['op-consume']);
    expect(find.text('Consume 5 mL of Ethanol'), findsNothing);
    expect(find.text('Add chemical Acetone'), findsOneWidget);
    expect(find.byKey(const Key('sync-retry-all')), findsNothing);
  });

  testWidgets('SYNC-01: empty queue explains itself', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryProvider.overrideWith(
            () => _FakeInventory(const InventoryState()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SyncCenterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nothing waiting'), findsOneWidget);
    expect(find.text('everything is on the server'), findsOneWidget);
    expect(find.text('No successful sync on this device yet.'), findsOneWidget);
  });
}
