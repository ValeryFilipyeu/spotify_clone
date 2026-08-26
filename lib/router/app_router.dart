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

/// All auth-driven navigation goes through redirect: no screen calls
/// context.go after a sign-in or a log-out. Screens only navigate for lateral
/// moves a redirect cannot know about, like the Sign Up / Log In links.
GoRouter createRouter(AuthBloc authBloc) {
  // Local, so hot reload never reuses a GlobalKey still attached to the
  // previous Navigator.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.landing,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final status = authBloc.state.status;
      final onAuthRoute = {
        Routes.landing,
        Routes.signUp,
        Routes.logIn,
      }.contains(state.matchedLocation);

      if (status == AuthStatus.unknown) return null;
      if (status == AuthStatus.unauthenticated && !onAuthRoute) return Routes.landing;
      if (status == AuthStatus.authenticated && onAuthRoute) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.landing, builder: (context, state) => const LandingPage()),
      GoRoute(path: Routes.signUp, builder: (context, state) => const SignUpPage()),
      GoRoute(path: Routes.logIn, builder: (context, state) => const LogInPage()),

      // Three tabs, each an independent Navigator, in shared chrome. Detail is a
      // child of each branch, so a playlist stacks inside the active tab.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomePage(),
                routes: [_detailRoute()],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.search,
                builder: (context, state) => const SearchPage(),
                routes: [_detailRoute()],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.library,
                builder: (context, state) => const LibraryPage(),
                routes: [_detailRoute()],
              ),
            ],
          ),
        ],
      ),

      // On the root navigator, so it covers the whole shell.
      GoRoute(
        path: Routes.player,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const FullPlayerPage(),
      ),
    ],
  );
}

/// The detail sub-route, built fresh per branch -- a GoRoute config is not meant
/// to be shared across parents. Relative, so the location is `/home/detail/dm1`.
GoRoute _detailRoute() => GoRoute(
  path: Routes.detailChild,
  builder: (context, state) => DetailPage(itemId: state.pathParameters['id']!),
);
