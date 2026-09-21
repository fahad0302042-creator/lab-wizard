import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../sync/presentation/sync_center_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final auth = ref.watch(authProvider);
    final inventory = ref.watch(inventoryProvider);
    final formMemory = ref.watch(formMemoryProvider);
    return Scaffold(
      body: NotebookPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(54, 12, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                const Expanded(child: PageHeading('settings')),
              ],
            ),
            const SizedBox(height: 12),
            NotebookCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.person_outline,
                    title: 'your account',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.user?.userMetadata?['name']?.toString() ?? 'Lab user',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    auth.user?.email ?? '',
                    style: TextStyle(color: context.mutedInkColor),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(authProvider.notifier).signOut();
                      if (context.mounted) {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            NotebookCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.palette_outlined,
                    title: 'appearance',
                  ),
                  RadioGroup<ThemeMode>(
                    groupValue: preferences.themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(preferencesProvider.notifier).setTheme(value);
                      }
                    },
                    child: const Column(
                      children: [
                        RadioListTile(
                          value: ThemeMode.system,
                          title: Text('Use phone setting'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile(
                          value: ThemeMode.light,
                          title: Text('Paper mode'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile(
                          value: ThemeMode.dark,
                          title: Text('Desk-lamp mode'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reduce motion'),
                    subtitle: const Text(
                      'Use instant transitions and fewer animated effects.',
                    ),
                    value: preferences.reduceMotion,
                    onChanged: ref
                        .read(preferencesProvider.notifier)
                        .setReduceMotion,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            NotebookCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.history_edu_outlined,
                    title: 'form memory',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The add and record sheets start from the unit, category, '
                    'low-stock level and amounts you used last. Kept on this '
                    'device for your account only.',
                    style: TextStyle(
                      color: context.mutedInkColor,
                      fontSize: 13,
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('prefill-threshold'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prefill low-stock level'),
                    value: formMemory.prefillThreshold,
                    onChanged: ref
                        .read(formMemoryProvider.notifier)
                        .setPrefillThreshold,
                  ),
                  SwitchListTile(
                    key: const Key('prefill-amount'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prefill last amount'),
                    subtitle: const Text(
                      'Per action: use, restock and damage each remember their own.',
                    ),
                    value: formMemory.prefillActionAmount,
                    onChanged: ref
                        .read(formMemoryProvider.notifier)
                        .setPrefillActionAmount,
                  ),
                  TextButton.icon(
                    key: const Key('forget-form-memory'),
                    onPressed: formMemory.isEmpty
                        ? null
                        : ref.read(formMemoryProvider.notifier).forget,
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                    label: const Text('Forget remembered values'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            NotebookCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.cloud_sync_outlined,
                    title: 'sync & offline copy',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    inventory.pendingCount == 0
                        ? 'Everything is synced. A private offline copy is kept on this device while you are signed in.'
                        : inventory.failedCount > 0
                        ? '${inventory.failedCount} change${inventory.failedCount == 1 ? '' : 's'} need${inventory.failedCount == 1 ? 's' : ''} attention in the sync center.'
                        : '${inventory.pendingCount} change${inventory.pendingCount == 1 ? '' : 's'} waiting for a connection.',
                  ),
                  if (inventory.lastSyncedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last successful sync ${relativeTime(inventory.lastSyncedAt!)}.',
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: inventory.refreshing
                            ? null
                            : ref.read(inventoryProvider.notifier).refresh,
                        icon: inventory.refreshing
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SyncCenterScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.list_alt_outlined),
                        label: Text(
                          inventory.pendingCount == 0
                              ? 'Open sync center'
                              : 'Sync center (${inventory.pendingCount})',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            NotebookCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.download_outlined,
                    title: 'export a backup',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${inventory.chemicals.length} chemicals · ${inventory.apparatus.length} apparatus · ${inventory.logs.length} log entries',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _exportCsv(context, inventory),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share inventory CSV'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Lab Wizard for Android · modern notebook edition',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedInkColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, InventoryState state) async {
    try {
      final rows = <List<String>>[
        [
          'type',
          'name',
          'formula/category',
          'quantity',
          'unit',
          'low stock level',
          'notes',
          'supplier',
          'cas number',
          'concentration',
          'location',
          'expiry date',
          'hazards',
        ],
        ...state.chemicals.map(
          (item) => [
            'chemical',
            item.name,
            item.formula,
            formatQuantity(item.quantity),
            item.unit,
            formatQuantity(item.lowStockThreshold),
            item.notes,
            item.supplier ?? '',
            item.casNumber ?? '',
            item.concentration ?? '',
            item.location ?? '',
            item.expiryDate == null ? '' : formatDateOnly(item.expiryDate!),
            item.hazardClasses.join(';'),
          ],
        ),
        ...state.apparatus.map(
          (item) => [
            'apparatus',
            item.name,
            item.category,
            formatQuantity(item.quantity),
            'pcs',
            formatQuantity(item.lowStockThreshold),
            item.notes,
            '',
            '',
            '',
            '',
            '',
            '',
          ],
        ),
      ];
      final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\n');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/lab-wizard-inventory.csv');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Lab Wizard inventory',
          text: 'Lab Wizard inventory backup',
          files: [XFile(file.path, mimeType: 'text/csv')],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not export: $error')));
    }
  }

  String _csvCell(String value) {
    final safe = RegExp(r'^[=+\-@]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: LabColors.marginRed),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Kalam',
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
