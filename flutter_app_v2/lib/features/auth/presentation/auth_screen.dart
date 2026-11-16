import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/build_info.dart';
import '../../../core/theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = ref.read(authProvider.notifier);
    if (_signUp) {
      await auth.signUp(_name.text, _email.text, _password.text);
    } else {
      await auth.signIn(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final auth = ref.watch(authProvider);

    if (auth.phase == AuthPhase.awaitingVerification) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mark_email_read_outlined, size: 40, color: lab.sage),
                const SizedBox(height: 16),
                Text('Check your inbox', style: context.title),
                const SizedBox(height: 8),
                Text(
                  'We sent a confirmation link to ${_email.text}. '
                  'Confirm it, then sign in.',
                  textAlign: TextAlign.center,
                  style: context.aside,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 32, 26, 32),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: lab.accentWash,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: lab.accent.withValues(alpha: .45),
                          ),
                        ),
                        child: Icon(
                          Icons.science_outlined,
                          size: 15,
                          color: lab.accent,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'LAB WIZARD',
                        style: context.label.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 2.2,
                          color: lab.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _signUp ? 'Start a shelf.' : 'Your shelf\nis waiting.',
                    style: context.display.copyWith(fontSize: 34),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _signUp
                        ? 'One account, same data as the web app.'
                        : 'Sign in with the account you already use. The '
                              'sensor turns the vessels; you can switch it off '
                              'in Settings.',
                    style: context.aside,
                  ),
                  const SizedBox(height: 30),
                  if (_signUp) ...[
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) => (value ?? '').contains('@')
                        ? null
                        : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                    validator: (value) => (value ?? '').length < 6
                        ? 'At least 6 characters'
                        : null,
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      auth.error!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: lab.berry,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: auth.isBusy ? null : _submit,
                      child: auth.isBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: auth.isBusy
                          ? null
                          : () => setState(() {
                              _signUp = !_signUp;
                              _form.currentState?.reset();
                            }),
                      child: Text(
                        _signUp
                            ? 'I already have an account'
                            : 'Create a new account',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      buildStamp,
                      style: context.label.copyWith(
                        fontSize: LabType.micro,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
