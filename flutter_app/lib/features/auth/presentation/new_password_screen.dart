import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';

/// Shown after a recovery link opened the app (ACCOUNT-01): choose and
/// confirm a new password.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(authProvider.notifier)
        .updatePassword(_password.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated. You are signed in.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider).user?.email ?? '';
    return Scaffold(
      body: NotebookPage(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(38, 28, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: NotebookCard(
                tape: NotebookTape.blue,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SketchTitle('choose a new password', fontSize: 30),
                      const SizedBox(height: 6),
                      Text(
                        email.isEmpty
                            ? 'The reset link signed you in. Pick a new '
                                  'password to finish.'
                            : 'The reset link signed you in as $email. Pick a '
                                  'new password to finish.',
                        style: TextStyle(color: context.mutedInkColor),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('new-password'),
                        controller: _password,
                        obscureText: _obscure,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').length < 6
                            ? 'Use at least 6 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('confirm-password'),
                        controller: _confirm,
                        obscureText: _obscure,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Repeat the new password',
                          prefixIcon: Icon(Icons.lock_reset),
                        ),
                        validator: (value) => value != _password.text
                            ? 'The passwords do not match'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('new-password-error'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: LabColors.marginRed,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        key: const Key('save-password'),
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(_saving ? 'Saving…' : 'Save password'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('skip-recovery'),
                        onPressed: _saving
                            ? null
                            : () => ref
                                  .read(authProvider.notifier)
                                  .skipRecovery(),
                        child: const Text('Not now, keep my password'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
