import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../diagnostics/diagnostics_providers.dart';

/// Settings card for crash diagnostics (OBS-01): opt-in switch, a plain
/// statement of what is kept and for how long, the stored reports, and
/// manual share / delete.
class DiagnosticsCard extends ConsumerWidget {
  const DiagnosticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(diagnosticsProvider);
    final controller = ref.read(diagnosticsProvider.notifier);
    final muted = TextStyle(color: context.mutedInkColor, fontSize: 12);
    return NotebookCard(
      key: const Key('diagnostics-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SketchTitle('crash reports', fontSize: 30),
          Text(
            'Off by default. When on, errors the app runs into are written '
            'to this phone only: the error message, the stack trace, which '
            'screen it happened on, the app build '
            '(${controller.appBuild}) and the Android version. Item names, '
            'notes, suppliers, locations, people, codes and your e-mail are '
            'removed before anything is stored. Reports are deleted after '
            '${diagnosticsRetention.inDays} days and only the newest '
            '$diagnosticsLimit are kept. Nothing is sent anywhere unless you '
            'share it yourself.',
            style: muted,
          ),
          SwitchListTile(
            key: const Key('diagnostics-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep crash reports on this phone'),
            subtitle: Text(
              diagnostics.enabled
                  ? '${diagnostics.reports.length} stored'
                  : 'Off',
            ),
            value: diagnostics.enabled,
            onChanged: diagnostics.ready ? controller.setEnabled : null,
          ),
          if (diagnostics.reports.isNotEmpty) ...[
            for (final report in diagnostics.reports.take(5))
              Padding(
                key: Key('diagnostic-${report.id}'),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.bug_report_outlined,
                      size: 16,
                      color: context.mutedInkColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${DateFormat('d MMM HH:mm').format(report.at.toLocal())}'
                        ' · ${report.kind.label} · ${report.headline}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (diagnostics.reports.length > 5)
              Text(
                '… and ${diagnostics.reports.length - 5} more in the export',
                style: muted,
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: const Key('diagnostics-share'),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      title: 'Lab Wizard crash reports',
                      subject: 'Lab Wizard crash reports',
                      text: controller.exportJson(),
                    ),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share reports'),
                ),
                TextButton.icon(
                  key: const Key('diagnostics-clear'),
                  onPressed: controller.clear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete all'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
