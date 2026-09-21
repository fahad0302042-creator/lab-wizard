import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [MockClient] whose responses carry the request they answer.
///
/// `MockClient` copies `request` from the handler's response, and the
/// PostgREST response parser reads `response.request!`, so a handler that
/// returns a plain `http.Response(...)` makes every table and RPC call fail
/// with a null-check error instead of the intended reply.
http.Client mockHttpClient(
  Future<http.Response> Function(http.Request request) handler,
) => MockClient((request) async {
  final response = await handler(request);
  return http.Response.bytes(
    response.bodyBytes,
    response.statusCode,
    request: request,
    headers: response.headers,
    reasonPhrase: response.reasonPhrase,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
  );
});
