import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../settings/presentation/data_export.dart';

/// The word that must be typed before the account can be deleted.
const deleteConfirmationWord = 'DELETE';

/// Two-step account deletion (ACCOUNT-03): export first, then a typed
/// confirmation plus the current password. Resolves to true once the
/// account is gone.
Future<bool?> showDeleteAccountSheet(
  BuildContext context, {
  Future<void> Function(InventoryState state)? export,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (_) => NotebookSheetFrame(
      child: DeleteAccountForm(export: export ?? shareFullExport),
    ),
  );
}

String _count(int n, String singular, [String? plural]) =>
    '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

class DeleteAccountForm extends ConsumerStatefulWidget {
  const DeleteAccountForm({required this.export, super.key});

  final Future<void> Function(InventoryState state) export;

  @override
  ConsumerState<DeleteAccountForm> createState() => _DeleteAccountFormState();
}

class _DeleteAccountFormState extends ConsumerState<DeleteAccountForm> {
  final _typed = TextEditingController();
  final _password = TextEditingController();
  bool _confirming = false;
  bool _exporting = false;
  bool _exported = false;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _typed.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canDelete =>
      _typed.text.trim() == deleteConfirmationWord &&
      _password.text.isNotEmpty &&
      !_deleting;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await widget.export(ref.read(inventoryProvider));
      if (mounted) setState(() => _exported = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .deleteAccount(password: _password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _deleting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final muted = context.mutedInkColor;
    final red = context.marginRedColor;
    final openLoans = inventory.checkouts.where((c) => c.isOpen).length;
    final openTasks = inventory.services.where((s) => s.isOpen).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SketchTitle(
          _confirming ? 'last check' : 'delete account',
          fontSize: 30,
        ),
        const SizedBox(height: 6),
        if (!_confirming) ...[
          Text(
            'This removes your account and everything in it, on every device '
            'and in the web app:',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          Text(
            '• ${_count(inventory.chemicals.length, 'chemical')} and '
            '${inventory.apparatus.length} apparatus\n'
            '• ${_count(inventory.logs.length, 'log entry', 'log entries')}\n'
            '• ${_count(openLoans, 'open loan')} and '
            '${_count(openTasks, 'open maintenance task')}\n'
            '• your sign-in itself',
            key: const Key('delete-summary'),
          ),
          const SizedBox(height: 10),
          Text(
            'Deletion is immediate and cannot be undone. Lab Wizard keeps no '
            'copy; only Supabase\'s routine backups age out on their own '
            'schedule. Export first if you might need the records.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('delete-export'),
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_exported ? Icons.check : Icons.download_outlined),
            label: Text(
              _exported ? 'Exported · export again' : 'Export my data first',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('delete-continue'),
            onPressed: _exporting
                ? null
                : () => setState(() => _confirming = true),
            style: FilledButton.styleFrom(backgroundColor: red),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Continue to delete'),
          ),
        ] else ...[
          Text(
            'Type $deleteConfirmationWord and enter your current password '
            'to delete the account permanently.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('delete-typed'),
            controller: _typed,
            enabled: !_deleting,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Type $deleteConfirmationWord',
              prefixIcon: const Icon(Icons.keyboard_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('delete-password'),
            controller: _password,
            enabled: !_deleting,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canDelete ? _delete() : null,
            decoration: const InputDecoration(
              labelText: 'Current password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                key: const Key('delete-error'),
                style: TextStyle(color: red, fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('delete-confirm'),
            onPressed: _canDelete ? _delete : null,
            style: FilledButton.styleFrom(backgroundColor: red),
            icon: _deleting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever),
            label: Text(
              _deleting ? 'Deleting…' : 'Delete my account permanently',
            ),
          ),
        ],
        TextButton(
          key: const Key('delete-cancel'),
          onPressed: _deleting || _exporting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Keep my account'),
        ),
      ],
    );
  }
}
