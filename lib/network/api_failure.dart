/// Everything that can go wrong between calling an endpoint and holding a
/// decoded response.
///
/// Sealed rather than a bag of loose Exception subclasses, and that is the whole
/// point of the type: a `switch` over an [ApiFailure] with no default branch is
/// checked for exhaustiveness by the compiler, so the day a fifth failure mode
/// is added, every place that turns a failure into a user-facing message stops
/// compiling until it says what to do about it. An untyped `catch (_)` -- which
/// is what the app did while every repository was a fake that only ever threw on
/// purpose -- cannot tell "you are offline" from "the server is broken" from
/// "we cannot read what the server sent", so it has to show one vague message
/// for all three.
///
/// Deliberately says nothing about how any of this should be *worded*: these are
/// facts about a request, and the copy shown to a user is a presentation
/// concern.
sealed class ApiFailure implements Exception {
  const ApiFailure(this.uri);

  /// The request that failed. Carried for logs -- the query string is usually
  /// the difference between "search is broken" and "search is broken for
  /// apostrophes".
  final Uri uri;

  /// A developer-facing explanation. Not for the UI.
  String get message;

  @override
  String toString() => '$runtimeType(${uri.path}): $message';
}

/// The request never reached the server, or its answer never came back: no
/// route to the host, DNS failure, a dropped connection, a captive portal, or
/// -- on the web only -- a cross-origin request the browser refused to hand
/// over. The browser reports that last case as an opaque network error on
/// purpose, so this is as specific as it can be.
final class NetworkUnreachable extends ApiFailure {
  const NetworkUnreachable(super.uri, this.cause);

  /// The underlying `ClientException`, whose text is platform-specific.
  final Object cause;

  @override
  String get message => 'could not reach the server ($cause)';
}

/// The connection opened but nothing completed inside the budget. Kept apart
/// from [NetworkUnreachable] because it means something different to a caller:
/// unreachable is worth retrying immediately, a timeout means the far end is
/// struggling and deserves a pause first.
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

  /// Worth retrying: the request was fine and the far end was momentarily not.
  /// A 4xx means the request itself was wrong, so repeating it verbatim will
  /// fail identically -- 429 excepted, which is explicitly "later, not never".
  bool get isTransient => statusCode >= 500 || statusCode == 429;

  @override
  String get message => 'HTTP $statusCode${serverMessage == null ? '' : ': $serverMessage'}';
}

/// The server answered with something that is not the shape we can read: not
/// JSON at all (an HTML error page from a proxy is the classic), not a JSON
/// object at the root, or an object missing a field the caller cannot do
/// without.
///
/// Its own case rather than being folded into [HttpErrorStatus] because the
/// status was fine -- a 200 whose body we cannot parse is a bug somewhere, and
/// one that retrying will not fix.
final class MalformedResponse extends ApiFailure {
  const MalformedResponse(super.uri, this.detail);

  final String detail;

  @override
  String get message => 'unreadable response: $detail';
}
