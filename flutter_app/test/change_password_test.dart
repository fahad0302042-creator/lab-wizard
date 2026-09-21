import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/auth/presentation/change_password_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

const _email = 'ali@example.org';

final _userJson = {
  'id': 'u1',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': _email,
  'app_metadata': <String, dynamic>{},
  'user_metadata': {'name': 'Ali'},
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

String _jwt() {
  String part(Map<String, Object?> map) =>
      base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': 'u1', 'aud': 'authenticated', 'role': 'authenticated', 'email': _email, 'exp': exp})}.sig';
}

/// GoTrue stand-in for sign-in, user update and scoped sign-out.
class _FakeGoTrue {
  final requests = <http.Request>[];
  String password = 'right';

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/auth/v1/token')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['password'] != password) {
        return http.Response(
          jsonEncode({
            'code': 400,
            'error_code': 'invalid_credentials',
            'msg': 'Invalid login credentials',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'access_token': _jwt(),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-${requests.length}',
          'user': _userJson,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/auth/v1/user') && request.method == 'PUT') {
      password = (jsonDecode(request.body) as Map)['password'] as String;
      return http.Response(
        jsonEncode(_userJson),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/auth/v1/logout')) {
      return http.Response('', 204);
    }
    return http.Response('{"msg":"not found"}', 404);
  });
}

class _FakeAuth extends AuthController {
  _FakeAuth({this.error});

  final String? error;
  final calls = <(String, String, bool)>[];

  @override
  AuthState build() => const AuthState(phase: AuthPhase.signedIn);

  @override
  Future<String?> changePassword({
    required String current,
    required String next,
    bool signOutOthers = false,
  }) async {
    calls.add((current, next, signOutOthers));
    return error;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AuthController.changePassword', () {
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
          autoRefreshToken: false,
        ),
      );
      addTearDown(client.dispose);
      container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
    });

    test(
      're-authenticates, then updates, then signs out other devices',
      () async {
        final auth = container.read(authProvider.notifier);
        await auth.signIn(_email, 'right');
        expect(container.read(authProvider).phase, AuthPhase.signedIn);
        server.requests.clear();

        expect(
          await auth.changePassword(current: 'wrong', next: 'new-secret'),
          'The current password is not right.',
        );
        expect(server.requests.map((r) => r.method), ['POST']);
        server.requests.clear();

        expect(
          await auth.changePassword(current: 'right', next: 'right'),
          'Choose a password different from the current one.',
        );
        expect(
          await auth.changePassword(current: '', next: 'x'),
          'Enter your current password.',
        );
        expect(server.requests, isEmpty);

        expect(
          await auth.changePassword(
            current: 'right',
            next: 'new-secret',
            signOutOthers: true,
          ),
          isNull,
        );
        expect(
          server.requests.map((r) => '${r.method} ${r.url.path}').toList(),
          ['POST /auth/v1/token', 'PUT /auth/v1/user', 'POST /auth/v1/logout'],
        );
        expect(server.requests.last.url.queryParameters['scope'], 'others');
        expect(server.password, 'new-secret');
        expect(container.read(authProvider).phase, AuthPhase.signedIn);
        expect(container.read(authProvider).user?.email, _email);
      },
    );

    test('needs a signed-in user', () async {
      expect(
        await container
            .read(authProvider.notifier)
            .changePassword(current: 'a', next: 'bbbbbb'),
        'Sign in again to change your password.',
      );
    });
  });

  group('ChangePasswordForm', () {
    Future<(_FakeAuth, List<bool?>)> pump(
      WidgetTester tester, {
      String? error,
    }) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _FakeAuth(error: error);
      final results = <bool?>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith(() => auth)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async =>
                        results.add(await showChangePasswordSheet(context)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (auth, results);
    }

    testWidgets('validates before calling the server', (tester) async {
      final (auth, results) = await pump(tester);
      await tester.enterText(
        find.byKey(const Key('current-password')),
        'old-1',
      );
      await tester.enterText(find.byKey(const Key('new-password')), 'old-1');
      await tester.enterText(
        find.byKey(const Key('confirm-password')),
        'old-1',
      );
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a password different from the current one.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('new-password')),
        'new-secret',
      );
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(auth.calls, isEmpty);

      await tester.enterText(
        find.byKey(const Key('confirm-password')),
        'new-secret',
      );
      await tester.tap(find.byKey(const Key('signout-others')));
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(auth.calls, [('old-1', 'new-secret', true)]);
      expect(results, [true]);
    });

    testWidgets('server errors stay in the sheet', (tester) async {
      final (auth, results) = await pump(
        tester,
        error: 'The current password is not right.',
      );
      await tester.enterText(
        find.byKey(const Key('current-password')),
        'old-1',
      );
      await tester.enterText(
        find.byKey(const Key('new-password')),
        'new-secret',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password')),
        'new-secret',
      );
      await tester.tap(find.byKey(const Key('save-password')));
      await tester.pumpAndSettle();
      expect(auth.calls, hasLength(1));
      expect(find.byKey(const Key('change-password-error')), findsOneWidget);
      expect(find.text('The current password is not right.'), findsOneWidget);
      expect(results, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });
}
