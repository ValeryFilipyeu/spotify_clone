/// Everything that can go wrong between calling an endpoint and holding a
/// decoded response.
///
/// Sealed so a `switch` with no default is checked for exhaustiveness: adding a
/// fifth failure mode breaks the build wherever failures become messages, rather
/// than silently joining the other four under one vague string.
///
/// Says nothing about wording. These are facts about a request.
sealed class ApiFailure implements Exception {
  const ApiFailure(this.uri);

  /// Carried for logs: the query string is usually the difference between
  /// "search is broken" and "search is broken for apostrophes".
  final Uri uri;

  /// A developer-facing explanation. Not for the UI.
  String get message;

  @override
  String toString() => '$runtimeType(${uri.path}): $message';
}

/// The request never reached the server, or its answer never came back: no
/// route, DNS, a dropped connection, a captive portal, or a CORS refusal on the
/// web. The browser reports that last one opaquely, so this is as specific as it
/// can be.
final class NetworkUnreachable extends ApiFailure {
  const NetworkUnreachable(super.uri, this.cause);

  /// The underlying `ClientException`, whose text is platform-specific.
  final Object cause;

  @override
  String get message => 'could not reach the server ($cause)';
}

/// The connection opened but nothing completed in time. Distinct from
/// [NetworkUnreachable]: that is worth retrying at once, this deserves a pause.
final class RequestTimeout extends ApiFailure {
  const RequestTimeout(super.uri, this.limit);

  final Duration limit;

  @override
  String get message => 'no response within ${limit.inSeconds}s';
}

/// The server answered, and said no.
final class HttpErrorStatus extends ApiFailure {
  const HttpErrorStatus(super.uri, this.statusCode, this.serverMessage);

  final int statusCode;

  /// Whatever the body offered by way of explanation, when it was readable.
  /// Audius answers a bad id with `{"code":400,"error":"invalid playlistId"}`.
  final String? serverMessage;

  /// The far end was momentarily unable, rather than the request being wrong.
  /// 429 counts: it is explicitly "later", not "never".
  bool get isTransient => statusCode >= 500 || statusCode == 429;

  @override
  String get message => 'HTTP $statusCode${serverMessage == null ? '' : ': $serverMessage'}';
}

/// The server answered with a shape we cannot read: not JSON (a proxy's HTML
/// error page is the classic), not an object, or missing a required field.
///
/// Its own case because the status was fine: a 200 we cannot parse is a bug, and
/// retrying will not fix it.
final class MalformedResponse extends ApiFailure {
  const MalformedResponse(super.uri, this.detail);

  final String detail;

  @override
  String get message => 'unreadable response: $detail';
}
