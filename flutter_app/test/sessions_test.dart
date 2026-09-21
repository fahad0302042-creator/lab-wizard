import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/settings/presentation/sessions_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _email = 'ali@example.org';

final _userJson = {
  'id': 'u1',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': _email,
  'email_confirmed_at': '2026-01-01T00:00:00Z',
  'last_sign_in_at': '2026-09-20T10:00:00Z',
  'app_metadata': {
    'provider': 'email',
    'providers': ['email'],
  },
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

class _FakeServer {
  final requests = <http.Request>[];

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/auth/v1/token')) {
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
    if (path.endsWith('/auth/v1/logout')) return http.Response('', 204);
    return http.Response('{"msg":"not found"}', 404);
  });

  Iterable<String> get logoutScopes => requests
      .where((r) => r.url.path.endsWith('/auth/v1/logout'))
      .map((r) => r.url.queryParameters['scope'] ?? '');
}

class _FakeLocal extends LocalDatabase {
  final cleared = <String>[];

  @override
  Future<void> clearUser(String userId) async => cleared.add(userId);
}

class _FakeAuth extends AuthController {
  _FakeAuth({this.othersError});

  final String? othersError;
  var others = 0;
  final signOuts = <bool>[];

  @override
  AuthState build() =>
      AuthState(phase: AuthPhase.signedIn, user: User.fromJson(_userJson));

  @override
  Future<String?> signOutOtherDevices() async {
    others++;
    return othersError;
  }

  @override
  Future<void> signOut({bool everywhere = false}) async {
    signOuts.add(everywhere);
    state = const AuthState(phase: AuthPhase.signedOut);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('SessionInfo reads what the user record offers', () {
    final info = SessionInfo.fromUser(User.fromJson(_userJson)!);
    expect(info.email, _email);
    expect(info.signedInAt, DateTime.parse('2026-09-20T10:00:00Z'));
    expect(info.accountCreatedAt, DateTime.parse('2026-01-01T00:00:00Z'));
    expect(info.providers, ['email']);
    expect(info.emailConfirmed, isTrue);
  });

  group('sign-out scopes', () {
    late _FakeServer server;
    late _FakeLocal local;
    late ProviderContainer container;

    setUp(() async {
      server = _FakeServer();
      local = _FakeLocal();
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
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          localDatabaseProvider.overrideWithValue(local),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).signIn(_email, 'pw');
    });

    test('other devices only', () async {
      final auth = container.read(authProvider.notifier);
      expect(await auth.signOutOtherDevices(), isNull);
      expect(server.logoutScopes, ['others']);
      await pumpEventQueue();
      expect(container.read(authProvider).phase, AuthPhase.signedIn);
      expect(local.cleared, isEmpty);
    });

    test('this phone only by default, everywhere on request', () async {
      final auth = container.read(authProvider.notifier);
      await auth.signOut();
      expect(server.logoutScopes, ['local']);
      expect(local.cleared, ['u1']);
      expect(container.read(authProvider).phase, AuthPhase.signedOut);

      await auth.signIn(_email, 'pw');
      await auth.signOut(everywhere: true);
      expect(server.logoutScopes, ['local', 'global']);
      expect(local.cleared, ['u1', 'u1']);
    });

    test('without a session there is nothing to revoke', () async {
      final auth = container.read(authProvider.notifier);
      await auth.signOut();
      expect(
        await auth.signOutOtherDevices(),
        'Sign in again to manage your sessions.',
      );
    });
  });

  group('SessionsCard', () {
    Future<_FakeAuth> pump(WidgetTester tester, {String? othersError}) async {
      final auth = _FakeAuth(othersError: othersError);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith(() => auth)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: SessionsCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('describes this device and signs out others after confirming', (
      tester,
    ) async {
      final auth = await pump(tester);
      expect(find.byKey(const Key('session-this-device')), findsOneWidget);
      expect(find.textContaining('Account since 1 Jan 2026'), findsOneWidget);
      expect(find.textContaining('email confirmed'), findsOneWidget);

      await tester.tap(find.byKey(const Key('signout-others')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out other devices?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.others, 0);

      await tester.tap(find.byKey(const Key('signout-others')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sessions-confirm')));
      await tester.pumpAndSettle();
      expect(auth.others, 1);
      expect(find.text('Other devices were signed out.'), findsOneWidget);
    });

    testWidgets('sign out everywhere calls the global sign-out', (
      tester,
    ) async {
      final auth = await pump(tester);
      await tester.tap(find.byKey(const Key('signout-everywhere')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out everywhere?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sessions-confirm')));
      await tester.pumpAndSettle();
      expect(auth.signOuts, [true]);
    });
  });
}
