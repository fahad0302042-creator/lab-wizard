import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_screen.dart';
import 'package:lab_wizard/features/inventory/presentation/inventory_sheets.dart';
import 'package:lab_wizard/features/inventory/presentation/service_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final scheduled = <(String, ServiceKind, String, String, DateTime?)>[];
  final completed = <(String, DateTime, String, String, String, DateTime?)>[];

  @override
  InventoryState build() => seed;

  @override
  Future<ApparatusService> scheduleService({
    required String apparatusId,
    required ServiceKind kind,
    required String title,
    required String note,
    DateTime? dueAt,
  }) async {
    scheduled.add((apparatusId, kind, title, note, dueAt));
    final service = ApparatusService(
      id: 'new-${scheduled.length}',
      apparatusId: apparatusId,
      kind: kind,
      title: title.trim(),
      note: note.trim(),
      dueAt: dueAt,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(services: [service, ...state.services]);
    return service;
  }

  @override
  Future<ApparatusService> completeService({
    required String serviceId,
    required DateTime completedAt,
    required String performedBy,
    required String result,
    required String note,
    DateTime? nextDueAt,
  }) async {
    completed.add((
      serviceId,
      completedAt,
      performedBy,
      result,
      note,
      nextDueAt,
    ));
    final updated = state.services
        .firstWhere((entry) => entry.id == serviceId)
        .copyWith(
          completedAt: completedAt,
          performedBy: performedBy,
          result: result,
        );
    state = state.copyWith(
      services: state.services
          .map((entry) => entry.id == serviceId ? updated : entry)
          .toList(),
    );
    return updated;
  }
}

Apparatus _gear(String id, String name) => Apparatus(
  id: id,
  name: name,
  category: 'electronics',
  quantity: 1,
  initialQuantity: 1,
  lowStockThreshold: 0,
  notes: '',
  createdAt: DateTime(2026, 1, 1),
);

ApparatusService _task(
  String id,
  String apparatusId, {
  ServiceKind kind = ServiceKind.maintenance,
  String title = '',
  DateTime? due,
  DateTime? done,
  String performedBy = '',
  String result = '',
}) => ApparatusService(
  id: id,
  apparatusId: apparatusId,
  kind: kind,
  title: title,
  dueAt: due,
  completedAt: done,
  performedBy: performedBy,
  result: result,
  createdAt: DateTime.now().subtract(const Duration(days: 10)),
);

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Future<_FakeInventory> _pump(
  WidgetTester tester, {
  required InventoryState seed,
  required void Function(BuildContext context, WidgetRef ref) open,
}) async {
  tester.view.physicalSize = const Size(420, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
            builder: (context, ref, _) {
              ref.watch(formMemoryProvider);
              return Center(
                child: FilledButton(
                  onPressed: () => open(context, ref),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('GEAR-03 state', () {
    test('urgent task picks overdue before due soon, soonest first', () {
      final overdue = _task(
        'late',
        'a1',
        kind: ServiceKind.calibration,
        due: _today().subtract(const Duration(days: 3)),
      );
      final soon = _task(
        'soon',
        'a1',
        due: _today().add(const Duration(days: 5)),
      );
      final sooner = _task(
        'sooner',
        'a1',
        due: _today().add(const Duration(days: 2)),
      );
      final far = _task(
        'far',
        'a1',
        due: _today().add(const Duration(days: 90)),
      );
      final doneLate = _task(
        'done',
        'a1',
        due: _today().subtract(const Duration(days: 30)),
        done: _today(),
      );
      expect(
        InventoryState(services: [soon, far, sooner])
            .urgentServiceFor('a1')
            ?.id,
        'sooner',
      );
      expect(
        InventoryState(services: [soon, overdue, sooner])
            .urgentServiceFor('a1')
            ?.id,
        'late',
      );
      expect(
        InventoryState(services: [far, doneLate]).urgentServiceFor('a1'),
        isNull,
      );
      expect(
        InventoryState(services: [far]).serviceStateFor('a1'),
        ExpiryState.ok,
      );
      expect(
        InventoryState(services: [soon, overdue]).serviceStateFor('a1'),
        ExpiryState.expired,
      );
      expect(
        InventoryState(services: [soon, far, doneLate])
            .serviceAlerts()
            .map((t) => t.id),
        ['soon'],
      );
      expect(serviceDueCaption(_task('x', 'a1')), 'no due date');
      expect(serviceDueCaption(overdue), 'overdue by 3 days');
    });
  });

  group('GEAR-03 sheets', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('item sheet lists open tasks with urgency and history', (
      tester,
    ) async {
      await _pump(
        tester,
        seed: InventoryState(
          apparatus: [_gear('a1', 'pH meter')],
          services: [
            _task(
              's1',
              'a1',
              kind: ServiceKind.calibration,
              title: 'Buffer check',
              due: _today().subtract(const Duration(days: 2)),
            ),
            _task('s2', 'a1', due: _today().add(const Duration(days: 40))),
            _task(
              's3',
              'a1',
              done: _today().subtract(const Duration(days: 1)),
              performedBy: 'Sara',
              result: 'pass',
            ),
          ],
        ),
        open: (context, ref) =>
            showItemDetailSheet(context, ref, ItemKind.apparatus, 'a1'),
      );
      await tester.ensureVisible(
        find.byKey(const Key('service-schedule-open')),
      );
      expect(find.byKey(const Key('service-s1')), findsOneWidget);
      expect(find.text('Buffer check'), findsOneWidget);
      expect(find.textContaining('overdue by 2 days'), findsOneWidget);
      expect(find.byKey(const Key('service-done-s1')), findsOneWidget);
      expect(find.byKey(const Key('service-s2')), findsOneWidget);
      expect(find.textContaining('due in 40 days'), findsOneWidget);
      expect(find.byKey(const Key('service-past-s3')), findsOneWidget);
      expect(find.text('Maintenance · pass'), findsOneWidget);
      // Once in the service history, once in the apparatus timeline (GEAR-04).
      expect(find.textContaining('by Sara'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('service-empty')), findsNothing);
    });

    testWidgets('schedule form validates the date and submits', (tester) async {
      final fake = await _pump(
        tester,
        seed: InventoryState(apparatus: [_gear('a1', 'pH meter')]),
        open: (context, ref) => showScheduleServiceSheet(context, 'a1'),
      );
      await tester.tap(find.byKey(const Key('service-kind-calibration')));
      await tester.pumpAndSettle();
      expect(find.text('Schedule Calibration'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('service-due')),
        '2026-13-40',
      );
      await tester.tap(find.byKey(const Key('service-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Use YYYY-MM-DD'), findsOneWidget);
      expect(fake.scheduled, isEmpty);

      await tester.enterText(
        find.byKey(const Key('service-title')),
        'Annual calibration',
      );
      await tester.tap(find.byKey(const Key('service-due-365')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('service-note')),
        'ISO 17025',
      );
      await tester.tap(find.byKey(const Key('service-submit')));
      await tester.pumpAndSettle();

      final (id, kind, title, note, due) = fake.scheduled.single;
      expect(id, 'a1');
      expect(kind, ServiceKind.calibration);
      expect(title, 'Annual calibration');
      expect(note, 'ISO 17025');
      expect(
        due,
        _today()
            .add(const Duration(days: 365))
            .add(const Duration(hours: 23, minutes: 59)),
      );
      expect(find.textContaining('Calibration due'), findsOneWidget);
    });

    testWidgets('complete form records result and schedules the next task', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        seed: InventoryState(
          apparatus: [_gear('a1', 'pH meter')],
          services: [
            _task('s1', 'a1', kind: ServiceKind.calibration, due: _today()),
            _task('s0', 'a1', done: _today(), performedBy: 'Sara'),
          ],
        ),
        open: (context, ref) => showCompleteServiceSheet(context, 's1'),
      );
      expect(find.text('Calibration done'), findsOneWidget);
      expect(find.byKey(const Key('service-person-Sara')), findsOneWidget);

      final future = _today().add(const Duration(days: 1));
      await tester.enterText(
        find.byKey(const Key('service-done-date')),
        '${future.year.toString().padLeft(4, '0')}-'
        '${future.month.toString().padLeft(2, '0')}-'
        '${future.day.toString().padLeft(2, '0')}',
      );
      await tester.tap(find.byKey(const Key('service-complete-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Cannot be in the future'), findsOneWidget);
      expect(fake.completed, isEmpty);

      final yesterday = _today().subtract(const Duration(days: 1));
      await tester.enterText(
        find.byKey(const Key('service-done-date')),
        '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}',
      );
      await tester.tap(find.byKey(const Key('service-person-Sara')));
      await tester.tap(find.byKey(const Key('service-result-adjusted')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('service-complete-note')),
        'offset 0.02',
      );
      await tester.ensureVisible(find.byKey(const Key('service-next-91')));
      await tester.tap(find.byKey(const Key('service-next-91')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('service-complete-submit')),
      );
      await tester.tap(find.byKey(const Key('service-complete-submit')));
      await tester.pumpAndSettle();

      final (id, completedAt, person, result, note, next) =
          fake.completed.single;
      expect(id, 's1');
      expect(completedAt, yesterday.add(const Duration(hours: 12)));
      expect(person, 'Sara');
      expect(result, 'adjusted');
      expect(note, 'offset 0.02');
      expect(
        next,
        _today().add(const Duration(days: 91, hours: 23, minutes: 59)),
      );
      expect(find.textContaining('Calibration done · next'), findsOneWidget);
    });

    testWidgets('shelf rows mark overdue and due-soon service', (tester) async {
      tester.view.physicalSize = const Size(420, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => _FakeInventory(
                InventoryState(
                  apparatus: [
                    _gear('a1', 'Balance'),
                    _gear('a2', 'Burette'),
                    _gear('a3', 'Centrifuge'),
                  ],
                  services: [
                    _task(
                      's1',
                      'a1',
                      kind: ServiceKind.calibration,
                      due: _today().subtract(const Duration(days: 1)),
                    ),
                    _task(
                      's2',
                      'a2',
                      due: _today().add(const Duration(days: 7)),
                    ),
                    _task(
                      's3',
                      'a3',
                      due: _today().add(const Duration(days: 120)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(kind: ItemKind.apparatus),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mark-service')), findsNWidgets(2));
      expect(find.text('calibration overdue'), findsOneWidget);
      expect(find.text('maintenance due'), findsOneWidget);
    });
  });
}
