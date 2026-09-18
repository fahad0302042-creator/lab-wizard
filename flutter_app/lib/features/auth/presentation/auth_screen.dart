import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (auth.phase == AuthPhase.setupRequired) return const _SetupRequired();
    if (auth.phase == AuthPhase.awaitingVerification) {
      return _VerificationNotice(email: _email.text);
    }

    return Scaffold(
      body: NotebookPage(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(38, 28, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: StaggerIn(
                index: 0,
                child: NotebookCard(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 76,
                            height: 76,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Lab Wizard',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Kalam',
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _signUp
                              ? 'start a new lab notebook'
                              : 'open your lab notebook',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.mutedInkColor),
                        ),
                        const SizedBox(height: 24),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          child: _signUp
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TextFormField(
                                    controller: _name,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Your name',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    validator: (value) =>
                                        (value ?? '').trim().isEmpty
                                        ? 'Enter your name'
                                        : null,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: (value) {
                            final email = (value ?? '').trim();
                            return email.contains('@')
                                ? null
                                : 'Enter a valid email';
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
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
                        if (auth.error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            auth.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: LabColors.marginRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: auth.isBusy ? null : _submit,
                          icon: auth.isBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _signUp
                                      ? Icons.auto_stories_outlined
                                      : Icons.login,
                                ),
                          label: Text(_signUp ? 'Create account' : 'Sign in'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: auth.isBusy
                              ? null
                              : () => setState(() {
                                  _signUp = !_signUp;
                                  _formKey.currentState?.reset();
                                }),
                          child: Text(
                            _signUp
                                ? 'I already have an account'
                                : 'Create a new account',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use the same account as the web app to load your existing data.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.mutedInkColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_signUp) {
      await ref
          .read(authProvider.notifier)
          .signUp(_name.text, _email.text, _password.text);
    } else {
      await ref.read(authProvider.notifier).signIn(_email.text, _password.text);
    }
  }
}

class _VerificationNotice extends StatelessWidget {
  const _VerificationNotice({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NotebookPage(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: NotebookCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: LabColors.green,
                  ),
                  const SizedBox(height: 16),
                  const SketchTitle('check your email', fontSize: 30),
                  Text(
                    'We sent a confirmation link to $email. Confirm it, then return and sign in.',
                    textAlign: TextAlign.center,
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

class _SetupRequired extends StatelessWidget {
  const _SetupRequired();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NotebookPage(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: EmptyNotebookState(
              icon: Icons.build_circle_outlined,
              title: 'backend not configured',
              message: 'Install an APK built by the GitHub workflow, or run with config/production.json.',
            ),
          ),
        ),
      ),
    );
  }
}
