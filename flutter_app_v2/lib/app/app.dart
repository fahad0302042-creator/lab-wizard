import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications/notification_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/vessel_tilt.dart';
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
    final theme = LabTheme.dark();
    return MaterialApp(
      title: 'Lab Wizard',
      debugShowCheckedModeBanner: false,
      // Instrument panel is a single, deliberate mode: a dim bench, a phone
      // propped against a bottle, and one accent colour that means "live".
      // There is no light theme to fall out of sync with it.
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
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

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  HomeTab _tab = HomeTab.dashboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await ref.read(inventoryProvider.notifier).bootstrap(widget.user.id);
      await ref.read(notificationServiceProvider).init();
      if (mounted) {
        await ref.read(preferencesProvider.notifier).refreshDailyReminder();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(preferencesProvider.notifier).refreshDailyReminder();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    // One tilt scope for every tab, inside the nav shell: the sensor is opened
    // once and closed when the shell goes away, not once per screen. Screens
    // brought up as routes (sheets, settings) open their own.
    return VesselTilt(
      enabled: ref.watch(preferencesProvider).tiltEnabled,
      child: Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // A single radial wash behind the top of every screen, so the canvas
          // is a lit surface rather than a flat black rectangle. Painted once,
          // behind the content, and never rebuilt.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-.7, -1),
                  radius: 1.2,
                  colors: [
                    context.lab.vignette.withValues(alpha: .55),
                    context.lab.canvas,
                  ],
                  stops: const [0, .62],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Center(
              // Keep very wide screens readable while allowing a two-column
              // shelf.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
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
        ],
      ),
      bottomNavigationBar: _Dock(
        current: _tab,
        onSelected: _open,
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        ),
      ),
      ),
    );
  }
}

/// The dock: one floating glass bar with five tabs and a settings control.
///
/// Tabs stay five and stay labelled, so nothing the old layout could reach
/// becomes unreachable. The selected tab is a filled accent cell rather than a
/// hairline underline — at arm's length, a filled shape is readable and a 2 px
/// rule is not.
class _Dock extends StatelessWidget {
  const _Dock({
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

  static const _icons = {
    HomeTab.dashboard: Icons.grid_view_rounded,
    HomeTab.chemicals: Icons.science_outlined,
    HomeTab.apparatus: Icons.biotech_outlined,
    HomeTab.scanner: Icons.qr_code_scanner,
    HomeTab.reports: Icons.bar_chart_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: lab.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: lab.hairStrong),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: .45),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final tab in HomeTab.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: current == tab,
                  label: _labels[tab],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelected(tab),
                    child: AnimatedContainer(
                      duration: LabMotionQuick.of(context),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: current == tab ? lab.accentWash : null,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: current == tab
                              ? lab.accent.withValues(alpha: .45)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _icons[tab],
                            size: 18,
                            color: current == tab ? lab.accent : lab.inkFaint,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _labels[tab]!,
                            style: context.label.copyWith(
                              fontSize: 8.5,
                              letterSpacing: .5,
                              color: current == tab ? lab.accent : lab.inkFaint,
                              fontWeight: current == tab
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 3),
            Container(width: 1, height: 26, color: lab.hair),
            SizedBox(
              width: 42,
              child: IconButton(
                tooltip: 'Settings',
                onPressed: onSettings,
                icon: Icon(Icons.tune, size: 18, color: lab.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local alias so the dock's short durations stay readable at the call site
/// without importing the whole motion library twice.
abstract final class LabMotionQuick {
  static Duration of(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180);
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
              Icon(Icons.power_off_outlined, size: 30, color: lab.inkFaint),
              const SizedBox(height: 14),
              Text('Not connected', style: context.title),
              const SizedBox(height: 8),
              Text(
                'This build has no backend settings. Install the APK from the '
                'GitHub release, or run with config/local.json.',
                textAlign: TextAlign.center,
                style: context.aside,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
