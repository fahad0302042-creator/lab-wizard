import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/lab_profile.dart';

/// Device-local report branding (REPORT-06).
final labProfileProvider = NotifierProvider<LabProfileController, LabProfile>(
  LabProfileController.new,
);

class LabProfileController extends Notifier<LabProfile> {
  static const key = 'lab_profile';

  @override
  LabProfile build() {
    unawaited(_restore());
    return const LabProfile();
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final stored = LabProfile.decode(preferences.getString(key));
    if (stored != state) state = stored;
  }

  Future<void> save(LabProfile profile) async {
    state = profile;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, profile.encode());
  }

  /// Copies [bytes] into the app's private documents folder so the logo
  /// survives the picker's temporary file going away.
  Future<void> setLogo(Uint8List bytes, {required String fileName}) async {
    final directory = await getApplicationDocumentsDirectory();
    final extension = p.extension(fileName).toLowerCase();
    final file = File(
      p.join(
        directory.path,
        'lab-logo${extension.isEmpty ? '.png' : extension}',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    await save(state.copyWith(logoPath: file.path));
  }

  Future<void> clearLogo() async {
    final path = state.logoPath;
    await save(state.copyWith(clearLogo: true));
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // The image is gone already; nothing else to clean up.
      }
    }
  }

  /// The logo bytes, or null when none is set or the file disappeared.
  Future<Uint8List?> logoBytes() async {
    final path = state.logoPath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }
}
