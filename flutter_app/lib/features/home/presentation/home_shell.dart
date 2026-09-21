import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../../notifications/notification_providers.dart';
import '../../notifications/presentation/alerts_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../scanner/presentation/scanner_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../sync/background/background_sync_providers.dart';
import '../../sync/presentation/sync_center_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.user, super.key});

  final User user;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(inventoryProvider.notifier).bootstrap(widget.user.id);
      ref.read(notificationCoordinatorProvider.notifier).start();
      ref.read(backgroundSyncCoordinatorProvider.notifier).start();
      final pending = ref.read(notificationCoordinatorProvider).pendingTap;
      if (pending != null && mounted) _openNotificationTarget(pending);
    });
  }

  /// Opens whatever a tapped notification points at (NOTIFY-01).
  void _openNotificationTarget(String payload) {
    ref.read(notificationCoordinatorProvider.notifier).consumeTap();
    final navigator = Navigator.of(context);
    final parts = payload.split(':');
    switch (parts.first) {
      case 'chemical' when parts.length > 1:
        showItemDetailSheet(context, ref, ItemKind.chemical, parts[1]);
      case 'apparatus' when parts.length > 1:
        showItemDetailSheet(context, ref, ItemKind.apparatus, parts[1]);
      case 'sync':
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const SyncCenterScreen()),
        );
      default:
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      notificationCoordinatorProvider.select((status) => status.pendingTap),
      (_, payload) {
        if (payload != null) _openNotificationTarget(payload);
      },
    );
    final pages = <Widget>[
      DashboardScreen(
        user: widget.user,
        onNavigate: _selectTab,
        onSettings: _openSettings,
      ),
      const InventoryScreen(kind: ItemKind.chemical),
      ScannerScreen(active: _index == 2),
      const InventoryScreen(kind: ItemKind.apparatus),
      const ReportsScreen(),
    ];
    return Scaffold(
      body: NotebookPage(
        includeSafeArea: false,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: List.generate(pages.length, (pageIndex) {
              return TickerMode(
                enabled: pageIndex == _index,
                child: KeyedSubtree(
                  key: ValueKey('main-page-$pageIndex'),
                  child: pages[pageIndex],
                ),
              );
            }),
          ),
        ),
      ),
      bottomNavigationBar: NotebookBottomNavigation(
        selectedIndex: _index,
        onSelected: _selectTab,
      ),
    );
  }

  void _selectTab(int value) {
    if (_index == value) return;
    HapticFeedback.selectionClick();
    setState(() => _index = value);
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}

class NotebookBottomNavigation extends StatelessWidget {
  const NotebookBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({String label, IconData icon, IconData selected})>[
    (label: 'home', icon: Icons.home_outlined, selected: Icons.home),
    (label: 'chems', icon: Icons.science_outlined, selected: Icons.science),
    (
      label: 'scan',
      icon: Icons.center_focus_weak,
      selected: Icons.center_focus_strong,
    ),
    (
      label: 'gear',
      icon: Icons.precision_manufacturing_outlined,
      selected: Icons.precision_manufacturing,
    ),
    (label: 'reports', icon: Icons.insights_outlined, selected: Icons.insights),
  ];

  @override
  Widget build(BuildContext context) {
    // Navigation chrome: labels grow with the system font up to 130 % and
    // the bar grows with them; beyond that they would crowd the icons
    // (A11Y-02). The labels are short and the icons carry the meaning.
    final labelScale = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3).scale(17) / 17;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.inkColor, width: 1.35)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70 + 17 * (labelScale - 1),
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = selectedIndex == index;
              final scan = index == 2;
              final color = selected
                  ? context.marginRedColor
                  : context.mutedInkColor;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.label,
                  child: InkResponse(
                    onTap: () => onSelected(index),
                    radius: 34,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (scan)
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: selected
                                    ? context.marginRedColor
                                    : context.cardColor,
                                border: Border.all(
                                  color: selected
                                      ? context.marginRedColor
                                      : context.inkColor,
                                  width: 2,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: selected
                                    ? const [
                                        BoxShadow(
                                          color: Color(0x33000000),
                                          offset: Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                selected ? item.selected : item.icon,
                                color: selected
                                    ? context.cardColor
                                    : context.inkColor,
                                size: 23,
                              ),
                            ),
                          )
                        else
                          AnimatedRotation(
                            turns: selected ? -.008 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              selected ? item.selected : item.icon,
                              color: color,
                              size: 25,
                            ),
                          ),
                        if (!scan) const SizedBox(height: 1),
                        Transform.translate(
                          offset: Offset(0, scan ? -5 : 0),
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontFamily: 'Caveat',
                              fontSize: 17,
                              height: .95,
                              fontWeight: FontWeight.w700,
                              decoration: selected
                                  ? TextDecoration.underline
                                  : null,
                              decorationThickness: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
      ),
    );
  }
}
