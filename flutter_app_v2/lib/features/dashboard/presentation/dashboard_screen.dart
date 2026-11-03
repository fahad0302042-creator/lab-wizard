import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/home_tabs.dart';
import '../../../app/providers.dart';
import '../../../core/build_info.dart';
import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_jar.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shelf/presentation/item_sheet.dart';

/// The first thing you see: what needs ordering, what happened today, and the
/// two doors you actually use — scan a label, or add something new.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({required this.onOpenTab, super.key});

  final ValueChanged<HomeTab> onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final auth = ref.watch(authProvider);
    final ordering = state.needsOrdering;
    final todayKey = localDayKey(DateTime.now());
    final today = state.logs
        .where((log) => localDayKey(log.loggedAt) == todayKey)
        .toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    final name = _firstName(auth.user?.userMetadata?['name']?.toString());

    return RefreshIndicator(
      onRefresh: () => ref.read(inventoryProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 110),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat(
                        'EEEE · d MMMM',
                      ).format(DateTime.now()).toUpperCase(),
                      style: context.label.copyWith(letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name == null ? 'The store room' : 'Hello, $name',
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.02,
                        letterSpacing: -1.4,
                        fontWeight: FontWeight.w600,
                        color: lab.ink,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                icon: Icon(Icons.tune, size: 20, color: lab.soft),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ShelfRowIn(
            index: 0,
            child: _OrderCard(ordering: ordering, onOpenTab: onOpenTab),
          ),
          const SizedBox(height: 10),
          ShelfRowIn(
            index: 1,
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: '${state.chemicals.length}',
                    label: 'reagents',
                    onTap: () => onOpenTab(HomeTab.chemicals),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(
                    value: '${state.apparatus.length}',
                    label: 'apparatus',
                    onTap: () => onOpenTab(HomeTab.apparatus),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(
                    value: '${today.length}',
                    label: 'logged today',
                    onTap: () => onOpenTab(HomeTab.reports),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DoorButton(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan a label',
                  onTap: () => onOpenTab(HomeTab.scanner),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DoorButton(
                  icon: Icons.add,
                  label: 'Add to shelf',
                  onTap: () => onOpenTab(HomeTab.chemicals),
                  secondary: true,
                ),
              ),
            ],
          ),
          if (state.pendingCount > 0) ...[
            const SizedBox(height: 14),
            _Note(
              text:
                  '${state.pendingCount} change'
                  '${state.pendingCount == 1 ? '' : 's'} still to upload. '
                  'They are safe on this phone.',
            ),
          ],
          const SizedBox(height: 22),
          Text('TODAY', style: context.label),
          const SizedBox(height: 8),
          if (today.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing logged yet. Swipe a row to log use, or scan a label.',
                style: context.aside.copyWith(fontSize: 16),
              ),
            )
          else
            for (var i = 0; i < today.length && i < 6; i++)
              _TodayRow(log: today[i], state: state, index: i),
          if (today.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+ ${today.length - 6} more today',
                style: context.aside.copyWith(fontSize: 15),
              ),
            ),
          const SizedBox(height: 22),
          const _AlertsCard(),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Lab Wizard 2 · ${buildStamp}',
              style: context.label.copyWith(fontSize: 8.5, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  static String? _firstName(String? full) {
    if (full == null || full.trim().isEmpty) return null;
    return full.trim().split(RegExp(r'\s+')).first;
  }
}

/// "1 thing needs ordering" reads better than a count of one.
String _orderHeadline(List<ItemView> items) {
  final count = items.length;
  if (count == 1) return '1 thing needs ordering';
  return '$count things need ordering';
}

/// The one card that earns the top of the screen: what to order.
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.ordering, required this.onOpenTab});

  final List<ItemView> ordering;
  final ValueChanged<HomeTab> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final calm = ordering.isEmpty;
    final accent = calm ? lab.sage : lab.clay;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: calm ? lab.card : accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: calm ? lab.hair : accent.withValues(alpha: .5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  calm ? 'Nothing needs ordering' : _orderHeadline(ordering),
                  style: context.label.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 1,
                    color: calm ? lab.soft : accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (calm)
            Text(
              'Every shelf is above its order level.',
              style: context.aside.copyWith(fontSize: 16),
            )
          else
            ...ordering.take(3).map((item) => _OrderLine(item: item)),
          if (ordering.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                onPressed: () => onOpenTab(HomeTab.chemicals),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(60, 34),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  'See the other ${ordering.length - 3}',
                  style: context.aside.copyWith(
                    fontSize: 15,
                    color: accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.item});

  final ItemView item;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final empty = item.quantity <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          GlassJar(metrics: item.metrics, width: 22, height: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.itemName.copyWith(fontSize: 14),
            ),
          ),
          Text(
            empty ? 'empty' : '${formatQuantity(item.quantity)} ${item.unit}',
            style: context.figure.copyWith(
              fontSize: 12.5,
              color: empty ? lab.berry : lab.clay,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.onTap});

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: lab.hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: -.8,
                color: lab.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.label.copyWith(fontSize: 8, letterSpacing: .8),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoorButton extends StatelessWidget {
  const _DoorButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: secondary ? Colors.transparent : lab.ink,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: secondary ? lab.hair : lab.ink),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: secondary ? lab.ink : lab.bone),
              const SizedBox(width: 8),
              Text(
                label,
                style: context.label.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 1,
                  color: secondary ? lab.ink : lab.bone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.log,
    required this.state,
    required this.index,
  });

  final ConsumptionLog log;
  final InventoryState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final item = state.chemicals
        .where((value) => value.id == log.itemId)
        .map(ItemView.fromChemical)
        .firstOrNull;
    final apparatus = state.apparatus
        .where((value) => value.id == log.itemId)
        .map(ItemView.fromApparatus)
        .firstOrNull;
    final name = item?.name ?? apparatus?.name ?? 'Removed item';
    final unit = item?.unit ?? (apparatus != null ? 'pcs' : '');
    final restock = log.action == InventoryAction.restock;

    return ShelfRowIn(
      index: index + 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => showItemSheet(
          context,
          itemId: log.itemId,
          kind: log.itemType,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                DateFormat('HH:mm').format(log.loggedAt.toLocal()),
                style: context.figure.copyWith(fontSize: 11.5, color: lab.soft),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.itemName.copyWith(fontSize: 14),
                ),
              ),
              Text(
                '${restock ? '+' : '−'}${formatQuantity(log.amount)} $unit',
                style: context.figure.copyWith(
                  fontSize: 12.5,
                  color: restock ? lab.sage : lab.clay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The notifications switch, on the surface where its consequences show up.
class _AlertsCard extends ConsumerStatefulWidget {
  const _AlertsCard();

  @override
  ConsumerState<_AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends ConsumerState<_AlertsCard> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final ok = await ref
        .read(preferencesProvider.notifier)
        .setLowStockAlerts(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (value && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for this app. Allow them in Android '
            'settings, then try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final on = ref.watch(preferencesProvider).lowStockAlerts;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lab.hair),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Low-stock alerts',
                  style: context.itemName.copyWith(fontSize: 14),
                ),
                Text(
                  on
                      ? 'A notification when a shelf drops to its order level.'
                      : 'Off. Nothing will interrupt you.',
                  style: context.aside.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: _busy ? null : _toggle,
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: lab.clay.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 15, color: lab.clay),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: context.aside.copyWith(fontSize: 14, color: lab.clay),
            ),
          ),
        ],
      ),
    );
  }
}
