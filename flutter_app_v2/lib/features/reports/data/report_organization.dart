import 'package:shared_preferences/shared_preferences.dart';

/// Report identity is stored on this device, alongside the optional logo.
class ReportOrganization {
  static const key = 'report_organization_name';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(key) ?? '').trim();
  }

  static Future<String> save(String name) async {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final prefs = await SharedPreferences.getInstance();
    final saved = cleaned.isEmpty
        ? await prefs.remove(key)
        : await prefs.setString(key, cleaned);
    if (!saved) throw StateError('Could not save organization name');
    return cleaned;
  }
}
