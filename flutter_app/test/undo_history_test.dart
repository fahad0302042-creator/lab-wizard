import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/data/inventory_repository.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final undone = <String>[];

  @override
  InventoryState build() => seed;

  @override
  Future<UndoResult> undoAction(String logId, {String reason = ''}) async {
    undone.add(logId);
    state = state.copyWith(
      logs: state.logs.where((log) => log.id != logId).toList(),
    );
    return const UndoResult();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('UX-04: history offers undo for recent entries only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final seed = InventoryState(
      chemicals: [
        Chemical(
          id: 'chem-1',
          name: 'Acetone',
          formula: 'C3H6O',
          unit: 'mL',
          quantity: 60,
          initialQuantity: 100,
          lowStockThreshold: 10,
          notes: '',
          qrCode: 'qr-1',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      logs: [
        ConsumptionLog(
          id: 'recent',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 40,
          note: 'titration',
          loggedAt: now.subtract(const Duration(hours: 2)),
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        ConsumptionLog(
          id: 'old',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.restock,
          amount: 100,
          note: '',
          loggedAt: now.subtract(const Duration(days: 20)),
          createdAt: now.subtract(const Duration(days: 20)),
        ),
      ],
      reversals: [
        InventoryReversal(
          id: 'rev-1',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 5,
          reversedAt: now.subtract(const Duration(minutes: 30)),
          originalLoggedAt: now.subtract(const Duration(days: 1)),
          originalNote: 'wrong bottle',
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: FilledButton(
                  onPressed: () => showItemDetailSheet(
                    context,
                    ref,
                    ItemKind.chemical,
                    'chem-1',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-log-recent')), findsOneWidget);
    expect(find.byKey(const Key('undo-recent')), findsOneWidget);
    expect(find.byKey(const Key('history-log-old')), findsOneWidget);
    expect(find.byKey(const Key('undo-old')), findsNothing);
    expect(find.byKey(const Key('history-undo-rev-1')), findsOneWidget);
    expect(find.textContaining('undone 30 min ago'), findsOneWidget);
    expect(find.textContaining('wrong bottle'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('undo-recent')));
    await tester.tap(find.byKey(const Key('undo-recent')));
    await tester.pumpAndSettle();
    expect(find.text('Undo consume of 40 mL?'), findsOneWidget);
    expect(find.textContaining('goes back to 100 mL'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Undo'));
    await tester.pumpAndSettle();
    expect(fake.undone, ['recent']);
    expect(find.byKey(const Key('history-log-recent')), findsNothing);
    expect(find.text('Change undone'), findsOneWidget);
  });
}
