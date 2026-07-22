import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/bloc/auth_bloc.dart';
import '../auth/bloc/auth_state.dart';
import '../detail/view/detail_page.dart';
import '../home/view/home_page.dart';
import '../landing/view/landing_page.dart';
import '../library/view/library_page.dart';
import '../log_in/view/log_in_page.dart';
import '../player/view/full_player_page.dart';
import '../search/view/search_page.dart';
import '../shell/view/scaffold_with_nav_bar.dart';
import '../sign_up/view/sign_up_page.dart';
import 'app_routes.dart';
import 'go_router_refresh_stream.dart';

/// All auth-driven navigation happens through redirect -- no screen ever
/// calls context.go(Routes.home) after a successful sign-up/log-in, and
/// Home's log-out button never calls context.go(Routes.landing) either.
/// Screens only call context.go for lateral moves a redirect cannot know
/// about (Landing -> Sign Up, the Sign Up <-> Log In footer links).
GoRouter createRouter(AuthBloc authBloc) {
  // Local (not a top-level global) so hot reload -- or a second createRouter --
  // never reuses a GlobalKey still attached to the previous Navigator.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.landing,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final status = authBloc.state.status;
      final onAuthRoute = {Routes.landing, Routes.signUp, Routes.logIn}.contains(state.matchedLocation);

      if (status == AuthStatus.unknown) return null;
      if (status == AuthStatus.unauthenticated && !onAuthRoute) return Routes.landing;
      if (status == AuthStatus.authenticated && onAuthRoute) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.landing, builder: (context, state) => const LandingPage()),
      GoRoute(path: Routes.signUp, builder: (context, state) => const SignUpPage()),
      GoRoute(path: Routes.logIn, builder: (context, state) => const LogInPage()),

      // The authenticated app: three tabs, each an independent Navigator (its
      // own back-stack + preserved state), wrapped in shared chrome (tab bar +
      // mini-player, see ScaffoldWithNavBar). Detail is a CHILD of each branch
      // so opening a playlist stacks INSIDE the active tab rather than covering
      // the tab bar.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomePage(),
              routes: [_detailRoute()],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.search,
              builder: (context, state) => const SearchPage(),
              routes: [_detailRoute()],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.library,
              builder: (context, state) => const LibraryPage(),
              routes: [_detailRoute()],
            ),
          ]),
        ],
      ),

      // Full-screen "Now Playing": pinned to the root navigator so it covers
      // the whole shell (tab bar + mini-player included).
      GoRoute(
        path: Routes.player,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const FullPlayerPage(),
      ),
    ],
  );
}

/// The detail sub-route, reused under each tab branch. A fresh instance per
/// call (a GoRoute config isn't meant to be shared across parents). Its path is
/// relative (`detail/:id`), so the full location becomes e.g. `/home/detail/dm1`.
GoRoute _detailRoute() => GoRoute(
      path: Routes.detailChild,
      builder: (context, state) => DetailPage(itemId: state.pathParameters['id']!),
    );
