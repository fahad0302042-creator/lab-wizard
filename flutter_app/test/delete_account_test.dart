import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/auth/presentation/delete_account_sheet.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _FakeServer {
  final requests = <http.Request>[];
  bool functionInstalled = true;
  bool offline = false;

  http.Client get client => MockClient((request) async {
    if (offline && request.url.path.contains('/rest/')) {
      throw const SocketException('offline');
    }
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/auth/v1/token')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['password'] != 'right') {
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
    if (path.endsWith('/rest/v1/rpc/delete_my_account')) {
      if (!functionInstalled) {
        return http.Response(
          jsonEncode({
            'code': 'PGRST202',
            'message':
                'Could not find the function public.delete_my_account without parameters in the schema cache',
            'details': null,
            'hint': null,
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 204);
    }
    if (path.endsWith('/auth/v1/logout')) {
      return http.Response(
        jsonEncode({'code': 403, 'msg': 'User from sub claim in JWT does not exist'}),
        403,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{"msg":"not found"}', 404);
  });
}

class _FakeLocal extends LocalDatabase {
  final cleared = <String>[];

  @override
  Future<void> clearUser(String userId) async => cleared.add(userId);
}

class _FakeAuth extends AuthController {
  _FakeAuth({this.error});

  final String? error;
  final passwords = <String>[];

  @override
  AuthState build() => const AuthState(phase: AuthPhase.signedIn);

  @override
  Future<String?> deleteAccount({required String password}) async {
    passwords.add(password);
    if (error == null) state = const AuthState(phase: AuthPhase.signedOut);
    return error;
  }
}

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the migration only adds the function and guards it', () {
    final sql = File('supabase/009_account_deletion.sql').readAsStringSync();
    expect(sql, contains('create or replace function public.delete_my_account()'));
    expect(sql, contains('auth.uid()'));
    expect(sql, contains('delete from auth.users where id = v_user_id'));
    expect(sql, contains('grant execute on function public.delete_my_account() to authenticated'));
    expect(sql, contains('revoke all on function public.delete_my_account() from anon'));
    expect(sql.toLowerCase(), isNot(contains('drop table')));
    expect(sql.toLowerCase(), isNot(contains('alter table')));
  });

  group('AuthController.deleteAccount', () {
    late _FakeServer server;
    late _FakeLocal local;
    late ProviderContainer container;

    setUp(() {
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
    });

    test('re-authenticates, calls the server function and wipes the phone', () async {
      final auth = container.read(authProvider.notifier);
      await auth.signIn(_email, 'right');
      server.requests.clear();

      expect(
        await auth.deleteAccount(password: 'wrong'),
        'The current password is not right.',
      );
      expect(server.requests.map((r) => r.url.path), ['/auth/v1/token']);
      expect(local.cleared, isEmpty);
      server.requests.clear();

      expect(await auth.deleteAccount(password: 'right'), isNull);
      expect(
        server.requests.map((r) => '${r.method} ${r.url.path}').toList(),
        [
          'POST /auth/v1/token',
          'POST /rest/v1/rpc/delete_my_account',
          'POST /auth/v1/logout',
        ],
      );
      expect(local.cleared, ['u1']);
      await pumpEventQueue();
      final state = container.read(authProvider);
      expect(state.phase, AuthPhase.signedOut);
      expect(state.notice, 'Your account and all its data were deleted.');
    });

    test('a missing server function becomes a setup hint', () async {
      server.functionInstalled = false;
      final auth = container.read(authProvider.notifier);
      await auth.signIn(_email, 'right');
      expect(
        await auth.deleteAccount(password: 'right'),
        startsWith('The server is missing the account-deletion function.'),
      );
      expect(local.cleared, isEmpty);
      expect(container.read(authProvider).phase, AuthPhase.signedIn);
    });

    test('offline deletion is refused before anything happens', () async {
      final auth = container.read(authProvider.notifier);
      await auth.signIn(_email, 'right');
      server.offline = true;
      expect(
        await auth.deleteAccount(password: 'right'),
        'You need to be online to delete the account.',
      );
      expect(local.cleared, isEmpty);
    });
  });

  group('DeleteAccountForm', () {
    Future<(_FakeAuth, List<bool?>, List<int>)> pump(
      WidgetTester tester, {
      String? error,
    }) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _FakeAuth(error: error);
      final results = <bool?>[];
      final exports = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => auth),
            inventoryProvider.overrideWith(
              () => _FakeInventory(
                InventoryState(
                  chemicals: [
                    Chemical(
                      id: 'c1',
                      name: 'Acetone',
                      formula: 'C3H6O',
                      unit: 'mL',
                      quantity: 1,
                      initialQuantity: 1,
                      lowStockThreshold: 0,
                      notes: '',
                      qrCode: 'q',
                      createdAt: DateTime(2026, 1, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async => results.add(
                      await showDeleteAccountSheet(
                        context,
                        export: (state) async =>
                            exports.add(state.chemicals.length),
                      ),
                    ),
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
      return (auth, results, exports);
    }

    testWidgets('exports first, then needs the word and the password', (
      tester,
    ) async {
      final (auth, results, exports) = await pump(tester);
      expect(find.textContaining('1 chemical and 0 apparatus'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-export')));
      await tester.pumpAndSettle();
      expect(exports, [1]);
      expect(find.text('Exported · export again'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-continue')));
      await tester.pumpAndSettle();
      FilledButton confirm() =>
          tester.widget<FilledButton>(find.byKey(const Key('delete-confirm')));
      expect(confirm().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('delete-typed')), 'delete');
      await tester.enterText(find.byKey(const Key('delete-password')), 'pw');
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('delete-typed')), 'DELETE');
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(auth.passwords, ['pw']);
      expect(results, [true]);
    });

    testWidgets('errors keep the sheet open and cancel keeps the account', (
      tester,
    ) async {
      final (auth, results, _) = await pump(
        tester,
        error: 'The current password is not right.',
      );
      await tester.tap(find.byKey(const Key('delete-continue')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('delete-typed')), 'DELETE');
      await tester.enterText(find.byKey(const Key('delete-password')), 'pw');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(auth.passwords, ['pw']);
      expect(find.byKey(const Key('delete-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-cancel')));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });
}
