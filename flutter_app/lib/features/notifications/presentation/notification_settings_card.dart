import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../notification_providers.dart';

/// Settings card for NOTIFY-01: master switch, per-topic switches, timing
/// options and a test button. Lives in the settings screen.
class NotificationSettingsCard extends ConsumerWidget {
  const NotificationSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(notificationPreferencesProvider);
    final status = ref.watch(notificationCoordinatorProvider);
    final controller = ref.read(notificationPreferencesProvider.notifier);
    final coordinator = ref.read(notificationCoordinatorProvider.notifier);
    final muted = TextStyle(color: context.mutedInkColor, fontSize: 13);

    Future<void> toggleMaster(bool value) async {
      if (!value) {
        await controller.update((current) => current.copyWith(enabled: false));
        return;
      }
      final granted = await coordinator.enable();
      if (!granted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are blocked for Lab Wizard in the system '
              'settings.',
            ),
          ),
        );
      }
    }

    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                color: LabColors.marginRed,
              ),
              const SizedBox(width: 8),
              const Text(
                'notifications',
                style: TextStyle(
                  fontFamily: 'Kalam',
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (status.busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Reminders come from this phone only: nothing is sent to a '
            'server. Alerts fire once a day per item; due dates are '
            'scheduled ahead so they arrive even when the app is closed.',
            style: muted,
          ),
          SwitchListTile(
            key: const Key('notify-master'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow notifications'),
            subtitle: Text(
              status.blocked
                  ? 'Blocked in the system settings'
                  : preferences.enabled
                  ? 'On · reminders at ${hourLabel(preferences.reminderHour)}'
                  : 'Off · the alerts list in the app still works',
            ),
            value: preferences.enabled,
            onChanged: status.busy ? null : toggleMaster,
          ),
          if (status.blocked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('notify-open-settings'),
                onPressed: () async {
                  await coordinator.openSystemSettings();
                  await coordinator.refreshPermission();
                },
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open system settings'),
              ),
            ),
          if (status.lastError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                status.lastError!,
                key: const Key('notify-error'),
                style: const TextStyle(
                  color: LabColors.marginRed,
                  fontSize: 13,
                ),
              ),
            ),
          const Divider(height: 8),
          _TopicSwitch(
            switchKey: const Key('notify-low'),
            title: 'Low and empty stock',
            subtitle: 'Uses each item\'s own low-stock level.',
            value: preferences.lowStock,
            onChanged: (value) =>
                controller.update((c) => c.copyWith(lowStock: value)),
          ),
          _TopicSwitch(
            switchKey: const Key('notify-expiry'),
            title: 'Chemical expiry',
            subtitle: 'Warns ahead of the expiry date and on the day.',
            value: preferences.expiry,
            onChanged: (value) =>
                controller.update((c) => c.copyWith(expiry: value)),
            trailing: _DaysDropdown(
              dropdownKey: const Key('notify-expiry-days'),
              value: preferences.expiryDays,
              options: NotificationPreferences.expiryDayOptions,
              enabled: preferences.expiry,
              onChanged: (value) =>
                  controller.update((c) => c.copyWith(expiryDays: value)),
            ),
          ),
          _TopicSwitch(
            switchKey: const Key('notify-returns'),
            title: 'Apparatus returns',
            subtitle: 'When a loan reaches its due time and while overdue.',
            value: preferences.returns,
            onChanged: (value) =>
                controller.update((c) => c.copyWith(returns: value)),
          ),
          _TopicSwitch(
            switchKey: const Key('notify-service'),
            title: 'Maintenance and calibration',
            subtitle: 'Ahead of each due date and on the day.',
            value: preferences.service,
            onChanged: (value) =>
                controller.update((c) => c.copyWith(service: value)),
            trailing: _DaysDropdown(
              dropdownKey: const Key('notify-service-days'),
              value: preferences.serviceDays,
              options: NotificationPreferences.serviceDayOptions,
              enabled: preferences.service,
              onChanged: (value) =>
                  controller.update((c) => c.copyWith(serviceDays: value)),
            ),
          ),
          _TopicSwitch(
            switchKey: const Key('notify-sync'),
            title: 'Sync problems',
            subtitle: 'When a change could not be saved to the server.',
            value: preferences.syncProblems,
            onChanged: (value) =>
                controller.update((c) => c.copyWith(syncProblems: value)),
          ),
          _TopicSwitch(
            switchKey: const Key('notify-weekly'),
            title: 'Weekly summary',
            subtitle:
                'Every ${weekdayNames[preferences.summaryWeekday]} at '
                '${hourLabel(preferences.summaryHour)}.',
            value: preferences.weeklySummary,
            onChanged: (value) =>
                controller.update((c) => c.copyWith(weeklySummary: value)),
          ),
          if (preferences.weeklySummary)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<int>(
                    key: const Key('notify-weekly-day'),
                    value: preferences.summaryWeekday,
                    isDense: true,
                    items: [
                      for (final entry in weekdayNames.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      controller.update(
                        (c) => c.copyWith(summaryWeekday: value),
                      );
                    },
                  ),
                  DropdownButton<int>(
                    key: const Key('notify-weekly-hour'),
                    value: preferences.summaryHour,
                    isDense: true,
                    items: [
                      for (final hour in withValue(
                        NotificationPreferences.hourOptions,
                        preferences.summaryHour,
                      ))
                        DropdownMenuItem(
                          value: hour,
                          child: Text(hourLabel(hour)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      controller.update((c) => c.copyWith(summaryHour: value));
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Expanded(child: Text('Reminder time')),
                DropdownButton<int>(
                  key: const Key('notify-hour'),
                  value: preferences.reminderHour,
                  isDense: true,
                  items: [
                    for (final hour in withValue(
                      NotificationPreferences.hourOptions,
                      preferences.reminderHour,
                    ))
                      DropdownMenuItem(
                        value: hour,
                        child: Text(hourLabel(hour)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    controller.update((c) => c.copyWith(reminderHour: value));
                  },
                ),
              ],
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                key: const Key('notify-test'),
                onPressed: preferences.enabled && !status.busy
                    ? coordinator.sendTest
                    : null,
                icon: const Icon(Icons.notifications_none, size: 18),
                label: const Text('Send a test notification'),
              ),
              const Spacer(),
              if (status.lastDispatchAt != null)
                Text(
                  '${status.scheduledCount} scheduled · '
                  '${relativeTime(status.lastDispatchAt!)}',
                  key: const Key('notify-status'),
                  style: muted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicSwitch extends StatelessWidget {
  const _TopicSwitch({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SwitchListTile(
            key: switchKey,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(title),
            subtitle: Text(subtitle),
            value: value,
            onChanged: onChanged,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}

class _DaysDropdown extends StatelessWidget {
  const _DaysDropdown({
    required this.dropdownKey,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final Key dropdownKey;
  final int value;
  final List<int> options;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      key: dropdownKey,
      value: value,
      isDense: true,
      items: [
        for (final days in withValue(options, value))
          DropdownMenuItem(value: days, child: Text('$days d')),
      ],
      onChanged: enabled
          ? (next) {
              if (next != null) onChanged(next);
            }
          : null,
    );
  }
}

/// [options] plus [value] when a saved preference is not one of the presets,
/// so the dropdown always has exactly one matching item.
List<int> withValue(List<int> options, int value) =>
    options.contains(value) ? options : ([...options, value]..sort());
