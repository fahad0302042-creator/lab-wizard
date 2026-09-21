/// Compile-time backend configuration.
///
/// Run with:
/// flutter run --dart-define-from-file=config/local.json
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// Deep link Supabase redirects to after a password-recovery email is
  /// opened (ACCOUNT-01). Must be listed under Authentication → URL
  /// configuration → Redirect URLs in the Supabase dashboard, and matches
  /// the `<data android:scheme … android:host …>` in AndroidManifest.xml.
  static const passwordResetScheme = 'com.labwizard.labwizard';
  static const passwordResetHost = 'reset-password';
  static const passwordResetRedirect =
      '$passwordResetScheme://$passwordResetHost';
}
