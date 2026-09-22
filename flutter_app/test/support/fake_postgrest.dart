import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'mock_http.dart';

/// Just enough of PostgREST to exercise conditional updates and RPC errors:
/// `eq`/`is` filters, PATCH/POST/DELETE, single-object responses and
/// scripted RPC functions.
class FakePostgrest {
  final tables = <String, List<Map<String, dynamic>>>{
    'chemicals': [],
    'apparatus': [],
    'consumption_logs': [],
  };
  final requests = <http.Request>[];
  final rpc = <String, http.Response Function(Map<String, dynamic> params)>{};
  bool offline = false;

  /// Optional script: return a response to answer [request] yourself (for
  /// example a 403 for one method), or null to let the fake handle it.
  http.Response? Function(http.Request request)? beforeRequest;

  http.Client get client => mockHttpClient(_handle);

  Iterable<http.Request> get patches =>
      requests.where((request) => request.method == 'PATCH');

  Map<String, dynamic> row(String table, String id) =>
      tables[table]!.firstWhere((row) => row['id'] == id);

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw const SocketException('offline');
    requests.add(request);
    final scripted = beforeRequest?.call(request);
    if (scripted != null) return scripted;
    final segments = request.url.pathSegments;
    if (segments.length >= 4 && segments[2] == 'rpc') {
      final handler = rpc[segments[3]];
      if (handler == null) {
        return error(
          404,
          'Could not find the function public.${segments[3]}',
          'PGRST202',
        );
      }
      return handler(jsonDecode(request.body) as Map<String, dynamic>);
    }
    final rows = tables.putIfAbsent(segments[2], () => []);
    final matched = rows
        .where((row) => matches(row, request.url.queryParameters))
        .toList();
    switch (request.method) {
      case 'GET':
        break;
      case 'PATCH':
        final changes = jsonDecode(request.body) as Map<String, dynamic>;
        for (final row in matched) {
          row.addAll(changes);
        }
      case 'POST':
        final body = jsonDecode(request.body);
        for (final item in body is List ? body : [body]) {
          rows.add(Map<String, dynamic>.from(item as Map));
          matched.add(rows.last);
        }
      case 'DELETE':
        rows.removeWhere(matched.contains);
      default:
        return error(405, 'Method not allowed', '405');
    }
    final accept = request.headers['Accept'] ?? '';
    if (accept.contains('object+json')) {
      if (matched.length != 1) {
        return http.Response(
          jsonEncode({
            'message': 'JSON object requested, multiple (or no) rows returned',
            'code': 'PGRST116',
            'details': 'Results contain ${matched.length} rows',
            'hint': null,
          }),
          406,
          headers: json,
        );
      }
      return http.Response(jsonEncode(matched.single), 200, headers: json);
    }
    return http.Response(jsonEncode(matched), 200, headers: json);
  }

  static const json = {'content-type': 'application/json; charset=utf-8'};

  static http.Response error(int status, String message, String code) =>
      http.Response(
        jsonEncode({
          'message': message,
          'code': code,
          'details': null,
          'hint': null,
        }),
        status,
        headers: json,
      );

  static bool matches(Map<String, dynamic> row, Map<String, String> query) {
    for (final entry in query.entries) {
      if (entry.key == 'select' || entry.key == 'columns') continue;
      final value = entry.value;
      final dot = value.indexOf('.');
      final operator = value.substring(0, dot);
      final operand = value.substring(dot + 1);
      final actual = row[entry.key];
      switch (operator) {
        case 'eq':
          if (!equal(actual, operand)) return false;
        case 'is':
          if (operand == 'null') {
            if (actual != null) return false;
          } else if (actual != (operand == 'true')) {
            return false;
          }
        default:
          throw UnsupportedError('operator $operator');
      }
    }
    return true;
  }

  static bool equal(Object? actual, String operand) {
    if (actual == null) return false;
    if (actual is num) {
      final number = num.tryParse(operand);
      return number != null && number == actual;
    }
    return actual.toString() == operand;
  }
}
