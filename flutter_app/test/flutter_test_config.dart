import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file: loads the app's bundled fonts so widget and
/// golden tests render the real handwriting faces instead of the test
/// framework's block glyphs (TEST-01). Layout tests therefore see the same
/// text metrics as a phone.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  await testMain();
}

Future<void> _loadFonts() async {
  const families = {
    'Caveat': ['assets/fonts/Caveat-Variable.ttf'],
    'Kalam': ['assets/fonts/Kalam-Regular.ttf', 'assets/fonts/Kalam-Bold.ttf'],
    'ArchitectsDaughter': ['assets/fonts/ArchitectsDaughter-Regular.ttf'],
    'PatrickHand': ['assets/fonts/PatrickHand-Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}
