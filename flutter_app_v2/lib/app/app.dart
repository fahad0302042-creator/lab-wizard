import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_screen.dart';
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
    if (auth.phase == AuthPhase.setupRequired) {
      return const _BackendMissing();
    }
    if (auth.phase == AuthPhase.signedIn && auth.user != null) {
      return HomeShell(user: auth.user!);
    }
    return const AuthScreen();
  }
}

/// The shelf is the app for now; the remaining tabs come after this one has
/// been through your hands.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.user, super.key});

  final User user;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(inventoryProvider.notifier).bootstrap(widget.user.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(bottom: false, child: ShelfScreen()),
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
