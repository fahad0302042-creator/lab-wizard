import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/home_tabs.dart';
import '../../../app/providers.dart';
import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/jar_metrics.dart';
import '../../../core/widgets/vessel_hero.dart';
import '../../../core/widgets/vessel_tilt.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import '../../reports/data/order_list.dart';
import '../../session/presentation/session_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shelf/presentation/item_sheet.dart';

/// The first thing you see: the instrument for whatever is closest to running
/// out, what needs ordering, and the two doors you actually use.
///
/// The screen is built as one column of facts, in the order they get asked:
/// "how much is left", "what do I need to buy", "what happened today". The
/// vessel at the top is a real reagent from the shelf, not a mascot, so every
/// pixel of it can be checked against a row further down.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({required this.onOpenTab, super.key});

  final ValueChanged<HomeTab> onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lab = context.lab;
    final state = ref.watch(inventoryProvider);
    final auth = ref.watch(authProvider);
    final preferences = ref.watch(preferencesProvider);
    final ordering = state.needsOrdering;
    final todayKey = localDayKey(DateTime.now());
    final today = state.logs
        .where((log) => localDayKey(log.loggedAt) == todayKey)
        .toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    final name = _firstName(auth.user?.userMetadata?['name']?.toString());
    final now = DateTime.now();
    final monthLogs = state.logs.where((log) {
      final date = log.loggedAt.toLocal();
      return date.year == now.year && date.month == now.month;
    });
    final usedCount = monthLogs
        .where((l) => l.action != InventoryAction.restock)
        .length;
    final addedCount = monthLogs
        .where((l) => l.action == InventoryAction.restock)
        .length;
    final emptyCount = [
      ...state.chemicals.map((i) => i.quantity),
      ...state.apparatus.map((i) => i.quantity),
    ].where((q) => q <= 0).length;

    // The instrument shows the thing that needs attention most: an item that is
    // empty or below its level, else the fullest shelf item as a baseline.
    final allItems = [
      ...state.chemicals.map(ItemView.fromChemical),
      ...state.apparatus.map(ItemView.fromApparatus),
    ];
    final hero = ordering.isNotEmpty
        ? ordering.first
        : (allItems.isNotEmpty ? allItems.first : null);

    // The shell already provides the tilt scope for every tab; nesting another
    // here would open a second sensor subscription for the same screen.
    return RefreshIndicator(
      onRefresh: () => ref.read(inventoryProvider.notifier).refresh(),
      color: lab.accent,
      backgroundColor: lab.surfaceRaised,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          _Header(
            name: name,
            pending: state.pendingCount,
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ShelfRowIn(
            index: 0,
            child: VesselHero(
              metrics: hero?.metrics ?? _emptyMetrics,
              name: hero?.name ?? 'Nothing on the shelf',
              formula: hero?.subtitle ?? '',
              quantityText: hero == null
                  ? '—'
                  : formatQuantity(hero.quantity),
              unit: hero?.unit ?? '',
              orderText: hero == null
                  ? 'add a reagent to begin'
                  : hero.metrics.hasLimit
                  ? 'order at ${formatQuantity(hero.threshold)} ${hero.unit}'
                  // Most imported rows have no capacity at all, so the order
                  // line is set on quantity, not on a fraction. Saying so is
                  // better than implying a full bottle that was never recorded.
                  : hero.metrics.levelUnknown
                  ? '${formatQuantity(hero.quantity)} ${hero.unit} on hand · '
                        'no order level'
                  : 'no order level set',
              placeholder: hero == null,
              onTap: hero == null
                  ? () => onOpenTab(HomeTab.chemicals)
                  : () => showItemSheet(
                      context,
                      itemId: hero.id,
                      kind: hero.kind,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          ShelfRowIn(
            index: 1,
            child: _OrderCard(
              ordering: ordering,
              onOpenTab: onOpenTab,
              onShare: () => shareOrderList(context, ordering),
            ),
          ),
          const SizedBox(height: 12),
          ShelfRowIn(
            index: 2,
            child: Row(
              children: [
                Expanded(
                  child: _DoorButton(
                    icon: Icons.qr_code_scanner,
                    label: 'Scan a label',
                    onTap: () => onOpenTab(HomeTab.scanner),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _DoorButton(
                    icon: Icons.playlist_add,
                    label: 'Log a session',
                    onTap: () => openSession(context),
                    secondary: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _StatStrip(
            reagents: state.chemicals.length,
            apparatus: state.apparatus.length,
            today: today.length,
            onTab: onOpenTab,
          ),
          const SizedBox(height: 10),
          _SyncLine(
            pending: state.pendingCount,
            error: state.error,
            fromCache: state.fromCache,
            loading: state.loading || state.refreshing,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('THIS MONTH', style: context.label),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: lab.hair)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Metric(
                value: '$usedCount',
                label: 'USED',
                onTap: () => onOpenTab(HomeTab.reports),
              ),
              _Metric(
                value: '$addedCount',
                label: 'RESTOCKED',
                onTap: () => onOpenTab(HomeTab.reports),
              ),
              _Metric(
                value: '$emptyCount',
                label: 'EMPTY NOW',
                accent: emptyCount > 0 ? lab.berry : null,
                onTap: () => onOpenTab(HomeTab.chemicals),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('TODAY', style: context.label),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: lab.hair)),
            ],
          ),
          const SizedBox(height: 8),
          if (today.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nothing logged yet. Swipe a row to log use, or scan a '
                'label — the number only changes when you confirm it.',
                style: context.aside,
              ),
            )
          else
            for (var i = 0; i < today.length && i < 6; i++)
              _TodayRow(log: today[i], state: state, index: i + 3),
          if (today.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+ ${today.length - 6} more today',
                style: context.aside.copyWith(fontSize: 12),
              ),
            ),
          const SizedBox(height: 20),
          _AlertsLine(
            on: preferences.lowStockAlerts,
            onOpenSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _emptyMetrics = JarMetrics(
    fill: 0,
    partialFill: 0,
    notch: null,
    ticks: 0,
    signal: StockSignal.fine,
    hasLimit: false,
  );

  static String? _firstName(String? full) {
    if (full == null || full.trim().isEmpty) return null;
    return full.trim().split(RegExp(r'\s+')).first;
  }
}

/// Date on the left, a live sync pill in the middle, settings on the right.
///
/// [pending] is a real count of queued changes, so "SYNCED" is only ever shown
/// when there is genuinely nothing waiting. The old green dot was decoration
/// that claimed a state it had not checked.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.pending,
    required this.onSettings,
  });

  final String? name;
  final int pending;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final synced = pending == 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEE, d MMM').format(DateTime.now()).toUpperCase(),
                style: context.label.copyWith(
                  fontSize: 9.5,
                  color: lab.inkFaint,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                name == null ? 'The store room' : 'Hello, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.display,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: synced
                ? lab.wash(lab.sage, .1)
                : lab.wash(lab.clay, .12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: synced
                  ? lab.sage.withValues(alpha: .3)
                  : lab.clay.withValues(alpha: .35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                synced ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                size: 12,
                color: synced ? lab.sage : lab.clay,
              ),
              const SizedBox(width: 4),
              Text(
                synced ? 'SYNCED' : '$pending WAITING',
                style: context.label.copyWith(
                  fontSize: 9,
                  letterSpacing: .7,
                  color: synced ? lab.sage : lab.clay,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Settings',
          onPressed: onSettings,
          icon: Icon(Icons.tune, size: 19, color: lab.inkSoft),
        ),
      ],
    );
  }
}

/// "1 thing needs ordering" reads better than a count of one.
String _orderHeadline(List<ItemView> items) {
  final count = items.length;
  if (count == 1) return '1 thing needs ordering';
  return '$count things need ordering';
}

/// The card that earns the space under the instrument: what to order, with the
/// vessel and the number visible per line, because a name alone is not enough
/// to decide to reorder.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.ordering,
    required this.onOpenTab,
    required this.onShare,
  });

  final List<ItemView> ordering;
  final ValueChanged<HomeTab> onOpenTab;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final calm = ordering.isEmpty;
    final accent = calm ? lab.sage : lab.clay;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: calm ? lab.surface : lab.wash(accent, .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: calm ? lab.hair : accent.withValues(alpha: .42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (calm ? 'Nothing needs ordering' : _orderHeadline(ordering))
                      .toUpperCase(),
                  style: context.label.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 1,
                    color: calm ? lab.inkSoft : accent,
                  ),
                ),
              ),
              if (!calm)
                Text(
                  '${ordering.length}',
                  style: context.figure.copyWith(
                    fontSize: 14,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          if (calm)
            Text(
              'Every shelf is above its order level. Items with no level set '
              'are never counted here.',
              style: context.aside.copyWith(fontSize: 12.5),
            )
          else
            ...ordering.take(3).map((item) => _OrderLine(item: item)),
          if (!calm)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (ordering.length > 3)
                    TextButton(
                      onPressed: () => onOpenTab(HomeTab.chemicals),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 34),
                        alignment: Alignment.centerLeft,
                        foregroundColor: accent,
                      ),
                      child: Text(
                        'See all ${ordering.length}',
                        style: context.label.copyWith(
                          fontSize: 10,
                          letterSpacing: .6,
                          color: accent,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onShare,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 34),
                      foregroundColor: accent,
                    ),
                    icon: const Icon(Icons.ios_share, size: 14),
                    label: Text(
                      'SHARE LIST',
                      style: context.label.copyWith(
                        fontSize: 10,
                        letterSpacing: .6,
                        color: accent,
                      ),
                    ),
                  ),
                ],
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
    final color = lab.forState(item.metrics.signal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          LeaningVessel(
            metrics: item.metrics,
            width: 20,
            height: 26,
            sensitivity: 1.8,
          ),
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
            style: context.figure.copyWith(fontSize: 12.5, color: color),
          ),
        ],
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
    final fg = secondary ? lab.ink : const Color(0xFF020617);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: secondary ? lab.surface : lab.accent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: secondary ? lab.hairStrong : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.label.copyWith(
                    fontSize: 10,
                    letterSpacing: .9,
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three counts in a single row of cells, divided by hairlines. Three boxes for
/// three numbers was a lot of furniture for something read in a glance.
class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.reagents,
    required this.apparatus,
    required this.today,
    required this.onTab,
  });

  final int reagents;
  final int apparatus;
  final int today;
  final ValueChanged<HomeTab> onTab;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Container(
      decoration: BoxDecoration(
        color: lab.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lab.hair),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _Cell(
            value: '$reagents',
            label: 'REAGENTS',
            onTap: () => onTab(HomeTab.chemicals),
          ),
          _Rule(color: lab.hair),
          _Cell(
            value: '$apparatus',
            label: 'APPARATUS',
            onTap: () => onTab(HomeTab.apparatus),
          ),
          _Rule(color: lab.hair),
          _Cell(
            value: '$today',
            label: 'LOGGED TODAY',
            onTap: () => onTab(HomeTab.reports),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.label, required this.onTap});

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            children: [
              Text(
                value,
                style: context.figure.copyWith(fontSize: 21, height: 1),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: context.label.copyWith(
                  fontSize: 8.5,
                  letterSpacing: .6,
                  color: lab.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: color);
}

/// A metric with a label under it, used for the month's two counts.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    this.accent,
    required this.onTap,
  });

  final String value;
  final String label;
  final Color? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: context.figure.copyWith(
                  fontSize: 26,
                  height: 1,
                  color: accent ?? lab.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: context.label.copyWith(
                  fontSize: 8.5,
                  letterSpacing: .7,
                  color: lab.inkFaint,
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
      index: index,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => showItemSheet(
          context,
          itemId: log.itemId,
          kind: log.itemType,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Text(
                DateFormat('HH:mm').format(log.loggedAt.toLocal()),
                style: context.label.copyWith(
                  fontSize: 10,
                  letterSpacing: .4,
                  color: lab.inkFaint,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: restock ? lab.sage : lab.clay,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
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

/// Says whether alerts are on, and where to change them. The switch itself
/// lives in Settings with the other preferences: two homes for one setting is
/// how settings drift apart.
class _AlertsLine extends StatelessWidget {
  const _AlertsLine({required this.on, required this.onOpenSettings});

  final bool on;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onOpenSettings,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(
              on
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              size: 14,
              color: on ? lab.accent : lab.inkFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                on ? 'Low-stock alerts are on' : 'Low-stock alerts are off',
                style: context.aside.copyWith(
                  fontSize: 12,
                  color: on ? lab.inkSoft : lab.inkFaint,
                ),
              ),
            ),
            Text(
              'SETTINGS',
              style: context.label.copyWith(
                fontSize: 9,
                color: lab.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sync state, in one line, stating the real thing rather than a reassuring
/// dot. A queued change is named as a queued change.
class _SyncLine extends StatelessWidget {
  const _SyncLine({
    required this.pending,
    required this.error,
    required this.fromCache,
    required this.loading,
  });

  final int pending;
  final String? error;
  final bool fromCache;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    // A plain if-chain rather than a pattern switch over four fields: the
    // precedence is the point (a queued change outranks a stale copy), and this
    // should read like the sentence it produces.
    final IconData icon;
    final Color color;
    final String text;
    if (pending > 0) {
      icon = Icons.cloud_upload_outlined;
      color = lab.clay;
      text = '$pending change${pending == 1 ? '' : 's'} kept on this phone, '
          'waiting to upload';
    } else if (error != null) {
      icon = Icons.error_outline;
      color = lab.berry;
      text = 'Sync needs attention. Details in Settings.';
    } else if (fromCache) {
      icon = Icons.save_outlined;
      color = lab.inkFaint;
      text = 'Showing the saved copy. Pull down to sync.';
    } else if (loading) {
      icon = Icons.sync;
      color = lab.inkFaint;
      text = 'Checking for updates…';
    } else {
      icon = Icons.check_circle_outline;
      color = lab.inkFaint;
      text = 'Up to date.';
    }
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: context.label.copyWith(
              fontSize: 9.5,
              letterSpacing: .4,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
