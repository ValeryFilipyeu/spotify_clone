/// Path string literals live here once, so no screen hardcodes a route
/// string.
abstract final class Routes {
  static const String landing = '/';
  static const String signUp = '/sign-up';
  static const String logIn = '/log-in';

  // --- Shell tabs (each is a StatefulShellBranch with its own navigator) ---
  static const String home = '/home';
  static const String search = '/search';
  static const String library = '/library';

  /// The detail screen is registered as a CHILD of each tab (so opening it
  /// stacks inside the active tab rather than covering the tab bar). This is
  /// the child segment pattern, e.g. `/home/detail/:id`.
  static const String detailChild = 'detail/:id';

  /// The full-screen "Now Playing" view. A root-level route (outside the
  /// shell) so it covers the tab bar and mini-player.
  static const String player = '/player';

  /// Builds a concrete detail location under a given tab base, so call sites
  /// never hand-format the path and the detail always stacks inside the tab it
  /// was opened from (e.g. `detailUnder(Routes.home, 'dm1')`).
  static String detailUnder(String tabBase, String itemId) => '$tabBase/detail/$itemId';
}
