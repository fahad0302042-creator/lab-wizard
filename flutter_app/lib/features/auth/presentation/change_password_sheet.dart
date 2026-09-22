import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/presentation/inventory_sheets.dart';

/// Change-password form (ACCOUNT-02). Resolves to true when the password
/// was changed.
Future<bool?> showChangePasswordSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const NotebookSheetFrame(child: ChangePasswordForm()),
  );
}

class ChangePasswordForm extends ConsumerStatefulWidget {
  const ChangePasswordForm({super.key});

  @override
  ConsumerState<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _signOutOthers = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .changePassword(
          current: _current.text,
          next: _next.text,
          signOutOthers: _signOutOthers,
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SketchTitle('change password', fontSize: 30),
          Text(
            'Confirm your current password first; the new one takes effect '
            'immediately on this phone.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('current-password'),
            controller: _current,
            obscureText: _obscure,
            autofocus: true,
            textInputAction: TextInputAction.next,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Current password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (value) =>
                (value ?? '').isEmpty ? 'Enter your current password.' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('new-password'),
            controller: _next,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) {
              final text = value ?? '';
              if (text.isNotEmpty && text == _current.text) {
                return 'Choose a password different from the current one.';
              }
              if (text.length < 6) return 'Use at least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('confirm-password'),
            controller: _confirm,
            obscureText: _obscure,
            enabled: !_saving,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Repeat the new password',
              prefixIcon: Icon(Icons.repeat),
            ),
            validator: (value) =>
                value != _next.text ? 'The passwords do not match' : null,
          ),
          CheckboxListTile(
            key: const Key('signout-others'),
            value: _signOutOthers,
            onChanged: _saving
                ? null
                : (value) => setState(() => _signOutOthers = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Also sign out my other devices'),
            subtitle: Text(
              'This phone stays signed in.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const Key('change-password-error'),
                style: TextStyle(
                  color: context.marginRedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          FilledButton.icon(
            key: const Key('save-password'),
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'Change password'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
