import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../data/organization_repository.dart';
import '../domain/active_notebook.dart';
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
  int _generation = 0;

  @override
  Lab? build() {
    ref.listen(authProvider, (previous, next) {
      if (previous?.user?.id == next.user?.id) return;
      _generation++;
      _remember(null);
      _restore();
    });
    _restore();
    return null;
  }

  static String _key(String userId) => 'active_lab_$userId';

  Future<void> _restore() async {
    final generation = ++_generation;
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_key(userId));
      if (savedId == null || savedId.isEmpty) {
        _remember(null);
        return;
      }
      // Block creates until the role is known, so a new item is not stamped
      // into Personal Lab and then hidden when the team lab appears.
      ref
          .read(activeNotebookProvider.notifier)
          .select(ActiveNotebook(labId: savedId, pending: true));

      final labs = await ref.read(userLabsProvider.future);
      final match = labs.where((l) => l.id == savedId).firstOrNull;
      // A tap that happened while restore was in flight wins.
      if (!ref.mounted || generation != _generation) return;
      _remember(match);
    } catch (_) {
      if (ref.mounted && generation == _generation) _remember(null);
    }
  }

  void _remember(Lab? lab) {
    state = lab;
    ref.read(activeNotebookProvider.notifier).select(ActiveNotebook.fromLab(lab));
  }

  Future<void> selectLab(Lab? lab) async {
    _generation++;
    _remember(lab);
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
