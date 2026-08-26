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

  /// A child segment of each tab, so detail stacks inside the active one:
  /// `/home/detail/:id`.
  static const String detailChild = 'detail/:id';

  /// Root-level, outside the shell, so it covers the tab bar and mini-player.
  static const String player = '/player';

  /// A detail location under a tab base, so detail always stacks inside the tab
  /// it was opened from: `detailUnder(Routes.home, 'dm1')`.
  static String detailUnder(String tabBase, String itemId) => '$tabBase/detail/$itemId';
}
