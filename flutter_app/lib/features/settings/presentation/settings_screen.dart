import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/csv.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../auth/presentation/change_password_sheet.dart';
import '../../auth/presentation/delete_account_sheet.dart';
import '../../import/presentation/import_screen.dart';
import '../../inventory/domain/models.dart';
import '../../notifications/presentation/notification_settings_card.dart';
import '../../sync/presentation/background_sync_card.dart';
import '../../sync/presentation/sync_center_screen.dart';
import 'app_lock_card.dart';
import 'diagnostics_card.dart';
import 'lab_profile_card.dart';
import '../../organizations/presentation/organization_card.dart';
import 'sessions_card.dart';

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
          padding: const EdgeInsets.fromLTRB(notebookGutter, 20, 18, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('change-password'),
                        onPressed: () async {
                          final changed = await showChangePasswordSheet(
                            context,
                          );
                          if (changed == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password changed.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.password_outlined),
                        label: const Text('Change password'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref.read(authProvider.notifier).signOut();
                          if (context.mounted) {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          }
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out (this phone)'),
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
            const NotificationSettingsCard(),
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
            const BackgroundSyncCard(),
            const SizedBox(height: 13),
            NotebookCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.download_outlined,
                    title: 'backup & import',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${inventory.chemicals.length} chemicals · ${inventory.apparatus.length} apparatus · ${inventory.logs.length} log entries. This backup includes every lab cached on this phone, not only the shelf you are viewing.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _exportCsv(context, inventory),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Share inventory CSV'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('open-import'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ImportScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Import CSV'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            const OrganizationCard(),
            const SizedBox(height: 13),
            const LabProfileCard(),
            const SizedBox(height: 13),
            const SessionsCard(),
            const SizedBox(height: 13),
            const AppLockCard(),
            const SizedBox(height: 13),
            const DiagnosticsCard(),
            const SizedBox(height: 13),
            // Pulls left onto the page's red margin line. Other cards stay
            // in the writing column.
            Container(
              margin: const EdgeInsets.only(left: -(notebookGutter - 10)),
              child: NotebookCard(
                accent: context.marginRedColor,
                padding: EdgeInsets.zero,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: context.marginRedColor, width: 6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CardTitle(
                          icon: Icons.warning_amber_outlined,
                          title: 'danger zone',
                          color: context.marginRedColor,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Deleting the account removes all chemicals, apparatus and '
                          'history from Lab Wizard for good. You can export '
                          'everything first.',
                          style: TextStyle(color: context.mutedInkColor),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('delete-account'),
                          onPressed: () async {
                            final deleted = await showDeleteAccountSheet(
                              context,
                            );
                            if (deleted == true && context.mounted) {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.marginRedColor,
                          ),
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text('Delete account…'),
                        ),
                      ],
                    ),
                  ),
                ),
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
          'serial number',
          'condition',
          'assigned to',
          'purchase date',
          'warranty until',
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
            '',
            '',
            '',
            '',
            '',
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
            item.location ?? '',
            '',
            '',
            item.serialNumber ?? '',
            item.condition ?? '',
            item.assignedTo ?? '',
            item.purchaseDate == null ? '' : formatDateOnly(item.purchaseDate!),
            item.warrantyUntil == null
                ? ''
                : formatDateOnly(item.warrantyUntil!),
          ],
        ),
      ];
      // REPORT-05: shared writer (formula guard, CRLF, byte-order mark).
      final csv = csvDocument(rows.first, rows.skip(1));
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/lab-wizard-inventory.csv');
      await file.writeAsBytes(csvBytes(csv), flush: true);
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
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, this.color});

  final IconData icon;
  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color ?? context.marginRedColor),
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
