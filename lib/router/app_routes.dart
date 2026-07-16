/// Path string literals live here once, so no screen hardcodes a route
/// string.
abstract final class Routes {
  static const String landing = '/';
  static const String signUp = '/sign-up';
  static const String logIn = '/log-in';
  static const String home = '/home';

  /// The route pattern registered with GoRouter (contains the `:id` param).
  static const String detail = '/detail/:id';

  /// Builds a concrete detail location for a given item id, so call sites
  /// never hand-format the path.
  static String detailFor(String itemId) => '/detail/$itemId';
}
