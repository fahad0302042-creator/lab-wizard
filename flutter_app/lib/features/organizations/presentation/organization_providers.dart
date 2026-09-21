import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../data/organization_repository.dart';
import '../domain/models.dart';

final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw StateError('Supabase client is required for OrganizationRepository');
  }
  return OrganizationRepository(client: client);
});

final userOrganizationsProvider = FutureProvider<List<Organization>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final repo = ref.watch(organizationRepositoryProvider);
  return repo.loadUserOrganizations();
});

final userLabsProvider = FutureProvider<List<Lab>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final repo = ref.watch(organizationRepositoryProvider);
  return repo.loadUserLabs();
});

class ActiveLabNotifier extends Notifier<Lab?> {
  @override
  Lab? build() {
    _restore();
    return null;
  }

  static String _key(String userId) => 'active_lab_$userId';

  Future<void> _restore() async {
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_key(userId));
      if (savedId == null || savedId.isEmpty) {
        state = null;
        return;
      }

      final labs = await ref.read(userLabsProvider.future);
      final match = labs.where((l) => l.id == savedId).firstOrNull;
      if (match != null && ref.mounted) {
        state = match;
      }
    } catch (_) {
      // Fallback cleanly to personal lab
    }
  }

  Future<void> selectLab(Lab? lab) async {
    state = lab;
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (lab == null) {
        await prefs.remove(_key(userId));
      } else {
        await prefs.setString(_key(userId), lab.id);
      }
    } catch (_) {}
  }
}

final activeLabProvider = NotifierProvider<ActiveLabNotifier, Lab?>(
  ActiveLabNotifier.new,
);
