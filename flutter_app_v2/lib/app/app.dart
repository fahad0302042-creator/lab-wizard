import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/inventory/domain/models.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/scanner/presentation/scanner_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shelf/presentation/shelf_screen.dart';
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
      const ShelfScreen(kind: ItemKind.chemical),
      const ShelfScreen(kind: ItemKind.apparatus),
      ScannerScreen(active: _index == 2),
      const ReportsScreen(),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: List.generate(
            pages.length,
            (page) => TickerMode(
              enabled: page == _index,
              child: pages[page],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        onSelected: (value) {
          if (_index == value) return;
          HapticFeedback.selectionClick();
          setState(() => _index = value);
        },
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        ),
      ),
    );
  }
}

/// Text-only tabs. No icons in the bar: the app already carries enough
/// furniture, and four words are faster to read than four glyphs.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onSelected,
    required this.onSettings,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings;

  static const _labels = ['CHEMS', 'APPARATUS', 'SCAN', 'REPORTS'];

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
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: index == i,
                    label: _labels[i],
                    child: InkResponse(
                      onTap: () => onSelected(i),
                      radius: 40,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _labels[i],
                              style: context.label.copyWith(
                                fontSize: 9.5,
                                letterSpacing: 1.3,
                                color: index == i ? lab.ink : lab.soft,
                                fontWeight: index == i
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: index == i ? 16 : 0,
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
              IconButton(
                tooltip: 'Settings',
                onPressed: onSettings,
                icon: Icon(Icons.tune, size: 19, color: lab.soft),
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
