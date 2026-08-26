import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_failure.dart';

/// Turns an HTTP GET into either a decoded JSON object or an [ApiFailure], so no
/// repository ever touches a status code or a `jsonDecode`.
///
/// `package:http`, not `dart:io`: the latter does not exist on the web and would
/// fail the build outright. It also normalises every platform's network error
/// into one [http.ClientException], so there is a single thing to catch.
class ApiClient {
  ApiClient({
    required this._baseUrl,
    http.Client? httpClient,
    this._defaultQuery = const {},
    this._timeout = const Duration(seconds: 10),
  }) : _client = httpClient ?? http.Client();

  final Uri _baseUrl;
  final http.Client _client;

  /// Appended to every request -- Audius' `app_name`, rather than ninety copies
  /// of it at the call sites.
  final Map<String, String> _defaultQuery;

  /// The whole round trip, not just connecting: some platforms never time out a
  /// merely slow request.
  final Duration _timeout;

  /// In-flight requests by url, so two callers share one round trip. Home builds
  /// several rows at once while Library resolves liked ids, so this is the normal
  /// case rather than an edge one.
  final Map<String, Future<Map<String, Object?>>> _inFlight = {};

  /// GETs [path] relative to the base url. A [query] value may be a `String` or
  /// a `List<String>` for repeated parameters (`?id=a&id=b`); nulls are dropped.
  ///
  /// Throws only [ApiFailure] subtypes.
  Future<Map<String, Object?>> getJson(String path, {Map<String, Object?> query = const {}}) {
    final uri = uriFor(path, query: query);
    final key = uri.toString();

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _get(uri);
    _inFlight[key] = request;
    // Forgotten however it settles: a kept failure would break the url for the
    // whole session. .ignore() is load-bearing -- whenComplete returns a second
    // future carrying the same error that nothing awaits.
    request.whenComplete(() => _inFlight.remove(key)).ignore();
    return request;
  }

  /// Builds the absolute url by *appending* [path] to the base url's segments.
  /// Public because audio and cover urls are built here too and handed to other
  /// widgets rather than fetched.
  ///
  /// Not `Uri.resolve`: it treats `/v1` as a file and replaces it, so
  /// `tracks/search` would resolve to `api.audius.co/tracks/search`.
  Uri uriFor(String path, {Map<String, Object?> query = const {}}) {
    final merged = <String, Object>{..._defaultQuery};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value != null) merged[entry.key] = value;
    }

    return _baseUrl.replace(
      pathSegments: [
        ..._baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        ...path.split('/').where((segment) => segment.isNotEmpty),
      ],
      queryParameters: merged.isEmpty ? null : merged,
    );
  }

  Future<Map<String, Object?>> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw RequestTimeout(uri, _timeout);
    } on http.ClientException catch (error) {
      throw NetworkUnreachable(uri, error);
    }

    // Before parsing: a proxy's HTML error page is not worth a parse error.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpErrorStatus(uri, response.statusCode, _serverMessage(response.body));
    }

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw MalformedResponse(uri, 'not JSON (${error.message})');
    }

    if (body is! Map<String, Object?>) {
      throw MalformedResponse(uri, 'expected a JSON object, got ${body.runtimeType}');
    }
    return body;
  }

  /// Best-effort explanation out of an error body, e.g. Audius'
  /// `{"code":400,"error":"invalid playlistId"}`. Never throws: describing a
  /// failure must not cause a second one.
  String? _serverMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) return decoded['error'].toString();
    } on FormatException {
      // Not JSON; the status code is all we have.
    }
    return null;
  }

  /// Releases the connection pool, including a client passed in: the app keeps
  /// one long-lived client, so nobody else needs it.
  void close() => _client.close();
}
