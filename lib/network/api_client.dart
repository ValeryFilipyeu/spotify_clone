import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_failure.dart';

/// One place where an HTTP GET becomes either a decoded JSON object or an
/// [ApiFailure]. Everything above it -- the repositories -- deals in domain
/// types and never touches a status code, a header or a `jsonDecode`.
///
/// Uses `package:http` rather than `dart:io`'s HttpClient because `dart:io` does
/// not exist on the web: importing it makes the web build fail outright, not at
/// runtime. `package:http`'s [http.Client] factory resolves to a browser
/// implementation there and a socket one everywhere else, and -- the part that
/// actually matters for the code below -- normalises every platform's network
/// error into one [http.ClientException], so there is a single thing to catch.
class ApiClient {
  /// The private fields are named directly as parameters: callers still pass
  /// `baseUrl:`/`defaultQuery:`/`timeout:`, because Dart derives the public
  /// argument name from the field. Only [httpClient] needs spelling out, since
  /// it falls back to a default rather than being stored as given.
  ApiClient({
    required this._baseUrl,
    http.Client? httpClient,
    this._defaultQuery = const {},
    this._timeout = const Duration(seconds: 10),
  }) : _client = httpClient ?? http.Client();

  final Uri _baseUrl;
  final http.Client _client;

  /// Appended to every request. An API-wide parameter (Audius asks callers to
  /// identify themselves with `app_name`) belongs here rather than being
  /// repeated at ninety call sites.
  final Map<String, String> _defaultQuery;

  /// A ceiling on the whole round trip, not just connecting. Without it a
  /// request that is merely *slow* rather than failed hangs its caller for as
  /// long as the platform's own default allows, which on some is never.
  final Duration _timeout;

  /// Requests currently in the air, keyed by their full url.
  ///
  /// Two callers asking for the same url get one round trip and share its
  /// result. This is not a micro-optimisation: the home screen builds several
  /// rows at once and the library resolves liked ids while it does, so the same
  /// url being wanted twice within a few hundred milliseconds is the normal
  /// case, not an edge one.
  final Map<String, Future<Map<String, Object?>>> _inFlight = {};

  /// GETs [path] relative to the base url and returns the decoded JSON object.
  ///
  /// A [query] value may be a `String`, or a `List<String>` for the parameters
  /// that are legitimately repeated (`?id=a&id=b`, which is how both of Audius'
  /// bulk endpoints take their ids). A null value is dropped, so optional
  /// parameters need no branching at the call site.
  ///
  /// Throws only [ApiFailure] subtypes.
  Future<Map<String, Object?>> getJson(String path, {Map<String, Object?> query = const {}}) {
    final uri = uriFor(path, query: query);
    final key = uri.toString();

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _get(uri);
    _inFlight[key] = request;
    // Forget it once it settles, whichever way it settled. Keeping a *failed*
    // future here would turn one flaky moment into a url that is broken for the
    // rest of the session, since every later caller would be handed the old
    // error instead of trying again.
    //
    // .ignore() is load-bearing: whenComplete hands back a second future that
    // completes with the same error, and nothing ever awaits that one, so
    // without it every failed request also raises an unhandled async error --
    // on top of the one the caller is already handling properly.
    request.whenComplete(() => _inFlight.remove(key)).ignore();
    return request;
  }

  /// Builds the absolute url by *appending* [path] to the base url's segments.
  ///
  /// Public because not every url is one this class fetches: a track's audio url
  /// is handed to the audio player and a cover's to an `Image` widget, and both
  /// still have to be built against the same base and default query. Better
  /// they come from here than be assembled by hand somewhere else.
  ///
  /// Not `Uri.resolve`, which would be wrong here: resolving `tracks/search`
  /// against `https://api.audius.co/v1` yields `https://api.audius.co/tracks/
  /// search`, because a last segment with no trailing slash counts as a file
  /// and gets replaced. Splitting and concatenating segments also makes the
  /// base url's trailing slash irrelevant, and percent-encodes each segment.
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

    // Checked before parsing, because the status is the more useful fact when
    // both are wrong -- a proxy's HTML error page is not worth a parse error.
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
  /// `{"code":400,"error":"invalid playlistId"}`. Returns null rather than
  /// throwing: a failed request must not be masked by a second failure while
  /// trying to describe the first.
  String? _serverMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) return decoded['error'].toString();
    } on FormatException {
      // Not JSON. Nothing to add beyond the status code.
    }
    return null;
  }

  /// Releases the underlying connection pool. Closes the [http.Client] this was
  /// given as well as one it made itself -- the app keeps a single long-lived
  /// client, so there is no case where someone else still needs it.
  void close() => _client.close();
}
