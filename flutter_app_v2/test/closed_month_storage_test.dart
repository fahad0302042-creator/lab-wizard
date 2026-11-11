import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard_v2/features/reports/data/closed_months.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('closing while reports load preserves the earlier closed month', () async {
    final old = ClosedMonth(
      monthKey: '2026-09',
      closedAt: DateTime(2026, 10),
      reports: const {},
      events: const {},
      lowStock: const {},
    );
    SharedPreferences.setMockInitialValues({
      'closed_months': jsonEncode({'2026-09': old.toJson()}),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(closedMonthsProvider.notifier);
    await controller.close([], DateTime(2026, 10));
    expect(container.read(closedMonthsProvider).keys, contains('2026-09'));
    expect(container.read(closedMonthsProvider).keys, contains('2026-10'));
    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(preferences.getString('closed_months')!) as Map;
    expect(saved.keys, containsAll(['2026-09', '2026-10']));
  });

  test('closing an already saved month cannot replace its snapshot', () async {
    final old = ClosedMonth(
      monthKey: '2026-10',
      closedAt: DateTime(2026, 11),
      reports: const {},
      events: const {'chemical': 4},
      lowStock: const {},
    );
    SharedPreferences.setMockInitialValues({
      'closed_months': jsonEncode({'2026-10': old.toJson()}),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(closedMonthsProvider.notifier);
    await expectLater(
      controller.close([], DateTime(2026, 10)),
      throwsStateError,
    );
    expect((await controller.closedFor(DateTime(2026, 10)))!.events['chemical'], 4);
  });

  test('unreadable saved reports are not overwritten', () async {
    SharedPreferences.setMockInitialValues({'closed_months': 'not json'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(closedMonthsProvider.notifier);
    await expectLater(
      controller.close([], DateTime(2026, 10)),
      throwsStateError,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('closed_months'), 'not json');
  });
}
