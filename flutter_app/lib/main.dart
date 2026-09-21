import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'features/diagnostics/diagnostics_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }
  // One container for the whole app so the crash-diagnostics hooks (OBS-01)
  // can reach the same providers as the widgets.
  final container = ProviderContainer();
  installDiagnosticsHooks(container);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LabWizardApp(),
    ),
  );
}
