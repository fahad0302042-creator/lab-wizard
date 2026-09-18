import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../scanner/presentation/scanner_screen.dart';
import '../../settings/presentation/settings_screen.dart';
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
    Future.microtask(
      () => ref.read(inventoryProvider.notifier).bootstrap(widget.user.id),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: NotebookPage(
        includeSafeArea: false,
        child: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: List.generate(pages.length, (pageIndex) {
              final active = pageIndex == _index;
              return TickerMode(
                enabled: active,
                child: ExcludeSemantics(
                  excluding: !active,
                  child: IgnorePointer(
                    ignoring: !active,
                    child: AnimatedOpacity(
                      opacity: active ? 1 : 0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: KeyedSubtree(
                        key: ValueKey('main-page-$pageIndex'),
                        child: pages[pageIndex],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
      bottomNavigationBar: _NotebookBottomNavigation(
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

class _NotebookBottomNavigation extends StatelessWidget {
  const _NotebookBottomNavigation({
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.inkColor, width: 1.35)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
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
    );
  }
}
