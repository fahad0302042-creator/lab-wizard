import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/build_info.dart';
import '../../../core/error_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/domain/models.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final preferences = ref.watch(preferencesProvider);
    final auth = ref.watch(authProvider);
    final inventory = ref.watch(inventoryProvider);

    return Scaffold(
      backgroundColor: lab.bone,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text('ACCOUNT', style: context.label),
          const SizedBox(height: 6),
          Text(
            auth.user?.userMetadata?['name']?.toString() ?? 'Lab user',
            style: context.itemName.copyWith(fontSize: 18),
          ),
          Text(auth.user?.email ?? '', style: context.formula),
          const SizedBox(height: 22),
          Text('APPEARANCE', style: context.label),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Desk-lamp mode'),
            subtitle: const Text('Dark paper for the evening shift'),
            value: preferences.themeMode == ThemeMode.dark,
            onChanged: (value) => ref
                .read(preferencesProvider.notifier)
                .setTheme(value ? ThemeMode.dark : ThemeMode.light),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduce motion'),
            subtitle: const Text('Instant transitions, no sloshing'),
            value: preferences.reduceMotion,
            onChanged: ref.read(preferencesProvider.notifier).setReduceMotion,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Low-stock alerts'),
            subtitle: const Text(
              'A notification when a shelf reaches its order level',
            ),
            value: preferences.lowStockAlerts,
            onChanged: (value) async {
              final ok = await ref
                  .read(preferencesProvider.notifier)
                  .setLowStockAlerts(value);
              if (!context.mounted || ok || !value) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Notifications are blocked for this app. Allow them in '
                    'Android settings, then try again.',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          Text('SYNC', style: context.label),
          const SizedBox(height: 8),
          Text(
            inventory.pendingCount == 0
                ? 'Everything is uploaded. A private copy of your shelf is '
                      'kept on this phone so it still opens without a '
                      'connection.'
                : '${inventory.pendingCount} change'
                      '${inventory.pendingCount == 1 ? '' : 's'} waiting to '
                      'upload.',
            style: TextStyle(fontSize: 13, height: 1.5, color: lab.soft),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: inventory.refreshing
                ? null
                : ref.read(inventoryProvider.notifier).refresh,
            icon: inventory.refreshing
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 17),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: 22),
          Text('EXPORT', style: context.label),
          const SizedBox(height: 8),
          Text(
            '${inventory.chemicals.length} reagents · '
            '${inventory.apparatus.length} apparatus · '
            '${inventory.logs.length} log entries',
            style: TextStyle(fontSize: 13, color: lab.soft),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _exportCsv(context, inventory),
            icon: const Icon(Icons.share_outlined, size: 17),
            label: const Text('Share inventory CSV'),
          ),
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: Icon(Icons.logout, size: 17, color: lab.berry),
            label: Text('Sign out', style: TextStyle(color: lab.berry)),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  'Lab Wizard 2 · the store room',
                  style: context.aside.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  buildStamp,
                  style: context.label.copyWith(fontSize: 9, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ],
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
          'order level',
          'notes',
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
          ],
        ),
        const <String>[],
        const ['date', 'item', 'action', 'amount', 'note'],
        ...state.logs.map(
          (log) => [
            DateFormat('yyyy-MM-dd').format(log.loggedAt.toLocal()),
            _nameOf(state, log.itemId),
            log.action.name,
            formatQuantity(log.amount),
            log.note,
          ],
        ),
      ];
      final csv = rows.map((row) => row.map(_cell).join(',')).join('\n');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/lab-wizard-inventory.csv');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Lab Wizard inventory',
          files: [XFile(file.path, mimeType: 'text/csv')],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  /// A CSV is read by people, so history rows name the item rather than
  /// quoting a database id.
  String _nameOf(InventoryState state, String itemId) {
    for (final item in state.chemicals) {
      if (item.id == itemId) return item.name;
    }
    for (final item in state.apparatus) {
      if (item.id == itemId) return item.name;
    }
    return 'Removed item';
  }

  /// Formula would be evaluated by a spreadsheet, so a leading operator is
  /// escaped rather than trusted.
  String _cell(String value) {
    final safe = RegExp(r'^[=+\-@]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }
}
