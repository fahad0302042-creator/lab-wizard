import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications/notification_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/inventory/domain/models.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/scanner/presentation/scanner_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shelf/presentation/shelf_screen.dart';
import 'home_tabs.dart';
import 'providers.dart';

class LabWizardApp extends ConsumerWidget {
  const LabWizardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    return MaterialApp(
      title: 'Lab Wizard',
      debugShowCheckedModeBanner: false,
      theme: LabTheme.light(),
      darkTheme: LabTheme.dark(),
      themeMode: preferences.themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations:
                media.disableAnimations || preferences.reduceMotion,
            textScaler: media.textScaler.clamp(maxScaleFactor: 1.6),
          ),
          child: child!,
        );
      },
      home: const _Gate(),
    );
  }
}

class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.phase == AuthPhase.setupRequired) return const _BackendMissing();
    if (auth.phase == AuthPhase.signedIn && auth.user != null) {
      return HomeShell(user: auth.user!);
    }
    return const AuthScreen();
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.user, super.key});

  final User user;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  HomeTab _tab = HomeTab.dashboard;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(inventoryProvider.notifier).bootstrap(widget.user.id);
      await ref.read(notificationServiceProvider).init();
    });
  }

  void _open(HomeTab tab) {
    if (_tab == tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(onOpenTab: _open),
      const ShelfScreen(kind: ItemKind.chemical),
      const ShelfScreen(kind: ItemKind.apparatus),
      ScannerScreen(active: _tab == HomeTab.scanner),
      const ReportsScreen(),
    ];
    final index = _tab.index;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          // A store-room app on a tablet should not stretch a 40-character row
          // across 10 inches: the eye loses the line. Held to a comfortable
          // column and centred, which is the cheapest honest tablet layout.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: IndexedStack(
              index: index,
              sizing: StackFit.expand,
              children: List.generate(
                pages.length,
                (page) =>
                    TickerMode(enabled: page == index, child: pages[page]),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _NavBar(
        current: _tab,
        onSelected: _open,
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        ),
      ),
    );
  }
}

/// Text-only tabs. Five labels do not fit as icons plus words, and four short
/// words are faster to read than five glyphs with a guess under each.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.current,
    required this.onSelected,
    required this.onSettings,
  });

  final HomeTab current;
  final ValueChanged<HomeTab> onSelected;
  final VoidCallback onSettings;

  /// Short words, because five tabs at ten pixels have to share a phone's
  /// width. "GEAR" is the store-room word for apparatus.
  static const _labels = {
    HomeTab.dashboard: 'HOME',
    HomeTab.chemicals: 'CHEMS',
    HomeTab.apparatus: 'GEAR',
    HomeTab.scanner: 'SCAN',
    HomeTab.reports: 'REPORTS',
  };

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: lab.bone,
        border: Border(top: BorderSide(color: lab.hair)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final tab in HomeTab.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: current == tab,
                    label: _labels[tab],
                    child: InkResponse(
                      onTap: () => onSelected(tab),
                      radius: 40,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _labels[tab]!,
                              style: context.label.copyWith(
                                fontSize: LabType.micro,
                                letterSpacing: .6,
                                color: current == tab ? lab.ink : lab.soft,
                                fontWeight: current == tab
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: current == tab ? 14 : 0,
                              height: 2,
                              decoration: BoxDecoration(
                                color: lab.sage,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: 46,
                child: IconButton(
                  tooltip: 'Settings',
                  onPressed: onSettings,
                  icon: Icon(Icons.tune, size: 18, color: lab.soft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackendMissing extends StatelessWidget {
  const _BackendMissing();

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Not connected',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.6,
                  color: lab.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This build has no backend settings. Install the APK from the '
                'GitHub release, or run with config/local.json.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: lab.soft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
