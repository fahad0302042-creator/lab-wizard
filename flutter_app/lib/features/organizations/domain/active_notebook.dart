import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

/// The notebook creates should land in, and whether this role may write.
///
/// Kept apart from the lab switcher so the inventory controller can read it
/// without an import cycle.
class ActiveNotebook {
  const ActiveNotebook({
    this.labId,
    this.organizationId,
    this.name,
    this.role,
    this.pending = false,
  });

  final String? labId;
  final String? organizationId;
  final String? name;
  final LabRole? role;

  /// A saved lab id is known, but its role has not been loaded yet.
  final bool pending;

  bool get isShared => (labId ?? '').trim().isNotEmpty;

  static ActiveNotebook fromLab(Lab? lab) => lab == null
      ? const ActiveNotebook()
      : ActiveNotebook(
          labId: lab.id,
          organizationId: lab.organizationId,
          name: lab.name,
          role: lab.userRole,
        );
}

class ActiveNotebookController extends Notifier<ActiveNotebook> {
  @override
  ActiveNotebook build() => const ActiveNotebook();

  void select(ActiveNotebook notebook) => state = notebook;
}

final activeNotebookProvider =
    NotifierProvider<ActiveNotebookController, ActiveNotebook>(
      ActiveNotebookController.new,
    );
