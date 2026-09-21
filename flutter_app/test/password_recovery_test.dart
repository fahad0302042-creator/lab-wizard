import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/config/app_config.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/auth/presentation/auth_screen.dart';
import 'package:lab_wizard/features/auth/presentation/new_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

final _user = User.fromJson({
  'id': 'u1',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'email': 'ali@example.org',
  'created_at': '2026-01-01T00:00:00Z',
})!;

class _FakeAuth extends AuthController {
  _FakeAuth(this.initial, {this.resetError, this.updateError});

  final AuthState initial;
  final String? resetError;
  final String? updateError;
  final resets = <String>[];
  final updates = <String>[];

  @override
  AuthState build() => initial;

  @override
  Future<String?> requestPasswordReset(String email) async {
    resets.add(email);
    return resetError;
  }

  @override
  Future<String?> updatePassword(String newPassword) async {
    updates.add(newPassword);
    if (updateError == null) {
      state = AuthState(phase: AuthPhase.signedIn, user: initial.user);
    }
    return updateError;
  }
}

/// GoTrue stand-in: records requests and answers /recover and /user.
class _FakeGoTrue {
  final requests = <http.Request>[];
  int recoverStatus = 200;

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/auth/v1/recover')) {
      if (recoverStatus == 200) return http.Response('{}', 200);
      return http.Response(
        jsonEncode({
          'code': 429,
          'error_code': 'over_email_send_rate_limit',
          'msg': 'For security purposes, you can only request this after 60 seconds.',
        }),
        429,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{"msg":"not found"}', 404);
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the Android manifest registers the redirect deep link', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      contains('android:scheme="${AppConfig.passwordResetScheme}"'),
    );
    expect(manifest, contains('android:host="${AppConfig.passwordResetHost}"'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(
      AppConfig.passwordResetRedirect,
      'com.labwizard.labwizard://reset-password',
    );
  });

  group('AuthController', () {
    late _FakeGoTrue server;
    late ProviderContainer container;

    setUp(() {
      server = _FakeGoTrue();
      final client = SupabaseClient(
        'http://fake.local',
        'test-key',
        httpClient: server.client,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      addTearDown(client.dispose);
      container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
    });

    test('requests the recovery email with the app redirect', () async {
      final error = await container
          .read(authProvider.notifier)
          .requestPasswordReset('  Ali@Example.org ');
      expect(error, isNull);
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/auth/v1/recover'));
      expect(
        request.url.queryParameters['redirect_to'],
        AppConfig.passwordResetRedirect,
      );
      expect(jsonDecode(request.body)['email'], 'Ali@Example.org');
    });

    test('rate limits and bad input become readable messages', () async {
      server.recoverStatus = 429;
      final auth = container.read(authProvider.notifier);
      expect(
        await auth.requestPasswordReset('ali@example.org'),
        'Too many attempts. Wait a minute and try again.',
      );
      expect(await auth.requestPasswordReset('nope'), 'Enter a valid email');
      expect(server.requests, hasLength(1));
    });

    test('updating the password without a session explains itself', () async {
      final auth = container.read(authProvider.notifier);
      expect(await auth.updatePassword('short'), 'Use at least 6 characters');
      expect(
        await auth.updatePassword('longer-secret'),
        startsWith('The reset link has expired.'),
      );
      expect(server.requests, isEmpty);
    });

    test('friendly messages', () {
      expect(
        friendlyAuthMessage(const AuthException('anything', statusCode: '429')),
        'Too many attempts. Wait a minute and try again.',
      );
      expect(
        friendlyAuthMessage(
          const AuthException(
            'New password should be different from the old password.',
          ),
        ),
        'Choose a password different from the current one.',
      );
      expect(friendlyAuthMessage(const AuthException('Custom')), 'Custom');
    });
  });

  group('screens', () {
    Widget app(_FakeAuth auth, Widget home) => ProviderScope(
      overrides: [authProvider.overrideWith(() => auth)],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('forgot password sends the link from the sign-in card', (
      tester,
    ) async {
      tall(tester);
      final auth = _FakeAuth(const AuthState(phase: AuthPhase.signedOut));
      await tester.pumpWidget(app(auth, const AuthScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reset-send')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(auth.resets, isEmpty);

      await tester.enterText(
        find.byKey(const Key('reset-email')),
        'ali@example.org',
      );
      await tester.tap(find.byKey(const Key('reset-send')));
      await tester.pumpAndSettle();
      expect(auth.resets, ['ali@example.org']);
      expect(find.byKey(const Key('reset-sent')), findsOneWidget);
      expect(find.textContaining('ali@example.org'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reset-done')));
      await tester.pumpAndSettle();
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('a reset error stays in the dialog', (tester) async {
      tall(tester);
      final auth = _FakeAuth(
        const AuthState(phase: AuthPhase.signedOut),
        resetError: 'Too many attempts. Wait a minute and try again.',
      );
      await tester.pumpWidget(app(auth, const AuthScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reset-email')),
        'ali@example.org',
      );
      await tester.tap(find.byKey(const Key('reset-send')));
      await tester.pumpAndSettle();
      expect(
        find.text('Too many attempts. Wait a minute and try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reset-sent')), findsNothing);
    });

    testWidgets('the new-password screen validates and saves', (tester) async {
      tall(tester);
      final auth = _FakeAuth(
        AuthState(phase: AuthPhase.passwordRecovery, user: _user),
      );
      await tester.pumpWidget(app(auth, const NewPasswordScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('ali@example.org'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('new-password')), 'secret-1');
      await tester.enterText(
        find.byKey(const Key('confirm-password')),
        'secret-2',
      );
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(auth.updates, isEmpty);

      await tester.enterText(
        find.byKey(const Key('confirm-password')),
        'secret-1',
      );
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(auth.updates, ['secret-1']);
      expect(find.text('Password updated. You are signed in.'), findsOneWidget);
    });

    testWidgets('server errors show inline and skipping keeps the session', (
      tester,
    ) async {
      tall(tester);
      final auth = _FakeAuth(
        AuthState(phase: AuthPhase.passwordRecovery, user: _user),
        updateError: 'Choose a password different from the current one.',
      );
      await tester.pumpWidget(app(auth, const NewPasswordScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-password')), 'secret-1');
      await tester.enterText(
        find.byKey(const Key('confirm-password')),
        'secret-1',
      );
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-password-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('skip-recovery')));
      await tester.pumpAndSettle();
      expect(_containerOf(tester).read(authProvider).phase, AuthPhase.signedIn);
    });
  });
}

// Not an extension: flutter_riverpod already adds `container` to WidgetTester.
ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NewPasswordScreen)));
