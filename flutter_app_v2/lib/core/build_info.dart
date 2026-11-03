/// The build that is actually running on this phone.
///
/// CI passes `--dart-define=BUILD_LABEL=2.0.<run number>` when it packages an
/// APK, so this string is a fingerprint: if a phone shows an older number, that
/// phone is running an older APK — no guessing required. Local runs, including
/// `flutter test`, fall back to `dev`.
const String kBuildLabel = String.fromEnvironment(
  'BUILD_LABEL',
  defaultValue: 'dev',
);

/// Shown at the bottom of the sign-in screen, settings and the dashboard.
String get buildStamp => 'build $kBuildLabel';
