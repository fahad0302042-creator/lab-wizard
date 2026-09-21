import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../background/background_sync.dart';
import '../background/background_sync_providers.dart';

/// Settings card for SYNC-03: master switch, frequency, Wi-Fi only, and
/// what the last background run did.
class BackgroundSyncCard extends ConsumerWidget {
  const BackgroundSyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(backgroundSyncPreferencesProvider);
    final controller = ref.read(backgroundSyncPreferencesProvider.notifier);
    final muted = TextStyle(color: context.mutedInkColor, fontSize: 13);

    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sync_lock_outlined, color: LabColors.marginRed),
              SizedBox(width: 8),
              Text(
                'background sync',
                style: TextStyle(
                  fontFamily: 'Kalam',
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Queued changes are sent and new changes downloaded while the '
            'app is closed. The app also syncs when you come back to it '
            'and when the connection returns.',
            style: muted,
          ),
          SwitchListTile(
            key: const Key('background-sync-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Sync in the background'),
            subtitle: Text(
              preferences.enabled
                  ? 'On · about every ${_hours(preferences.everyHours)}'
                        '${preferences.unmeteredOnly ? ' on Wi-Fi' : ''}'
                  : 'Off · only when the app is open',
            ),
            value: preferences.enabled,
            onChanged: (value) => controller.update(
              (current) => current.copyWith(enabled: value),
            ),
          ),
          if (preferences.enabled) ...[
            Row(
              children: [
                const Expanded(child: Text('How often')),
                DropdownButton<int>(
                  key: const Key('background-sync-frequency'),
                  value: preferences.everyHours,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final hours in BackgroundSyncPreferences.hourOptions)
                      DropdownMenuItem(
                        value: hours,
                        child: Text('every ${_hours(hours)}'),
                      ),
                  ],
                  onChanged: (hours) {
                    if (hours == null) return;
                    controller.update(
                      (current) => current.copyWith(everyHours: hours),
                    );
                  },
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('background-sync-wifi-only'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Wi-Fi only'),
              subtitle: const Text('Skip background runs on mobile data.'),
              value: preferences.unmeteredOnly,
              onChanged: (value) => controller.update(
                (current) => current.copyWith(unmeteredOnly: value),
              ),
            ),
            Text(
              'Android picks the exact moment and may wait for the phone '
              'to be idle or charging; battery savers can delay it further.',
              style: muted,
            ),
          ],
          const SizedBox(height: 8),
          const BackgroundSyncSummary(),
        ],
      ),
    );
  }

  static String _hours(int hours) => hours == 1 ? 'hour' : '$hours hours';
}

/// One or two lines about the last background run; used by the settings
/// card and the sync center.
class BackgroundSyncSummary extends ConsumerWidget {
  const BackgroundSyncSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      backgroundSyncCoordinatorProvider.select((state) => state.status),
    );
    final muted = TextStyle(color: context.mutedInkColor, fontSize: 12.5);
    final ranAt = status.lastRunAt;
    if (ranAt == null) {
      return Text(
        'No background run yet.',
        key: const Key('background-sync-status'),
        style: muted,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last background run ${relativeTime(ranAt)} '
          '(${status.lastTask ?? 'sync'}): ${status.lastResult ?? 'done'}.',
          key: const Key('background-sync-status'),
          style: status.failed
              ? const TextStyle(color: LabColors.marginRed, fontSize: 12.5)
              : muted,
        ),
        if (status.lastError != null)
          Text(
            friendlyErrorMessage(status.lastError!),
            key: const Key('background-sync-error'),
            style: const TextStyle(color: LabColors.marginRed, fontSize: 12),
          ),
      ],
    );
  }
}
