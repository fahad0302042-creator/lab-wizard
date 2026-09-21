import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';

/// Asks for the account email and sends the recovery link (ACCOUNT-01).
Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ForgotPasswordDialog(initialEmail: initialEmail),
  );
}

class ForgotPasswordDialog extends ConsumerStatefulWidget {
  const ForgotPasswordDialog({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<ForgotPasswordDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final address = _email.text.trim();
    if (!address.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .requestPasswordReset(address);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      _sent = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    return AlertDialog(
      title: Text(_sent ? 'Check your email' : 'Reset your password'),
      content: _sent
          ? Text(
              'If an account exists for ${_email.text.trim()}, a reset link '
              'is on its way. Open it on this phone: it brings you straight '
              'back here to choose a new password. The link is valid for a '
              'limited time and works once.',
              key: const Key('reset-sent'),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We will email you a link that opens Lab Wizard on this '
                  'phone so you can choose a new password.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('reset-email'),
                  controller: _email,
                  autofocus: widget.initialEmail.isEmpty,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !_sending,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.alternate_email),
                    errorText: _error,
                  ),
                ),
              ],
            ),
      actions: _sent
          ? [
              FilledButton(
                key: const Key('reset-done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('reset-send'),
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send link'),
              ),
            ],
    );
  }
}
