import 'package:go_router/go_router.dart';

import '../auth/bloc/auth_bloc.dart';
import '../auth/bloc/auth_state.dart';
import '../home/view/home_page.dart';
import '../landing/view/landing_page.dart';
import '../log_in/view/log_in_page.dart';
import '../sign_up/view/sign_up_page.dart';
import 'app_routes.dart';
import 'go_router_refresh_stream.dart';

/// All auth-driven navigation happens through redirect -- no screen ever
/// calls context.go(Routes.home) after a successful sign-up/log-in, and
/// Home's log-out button never calls context.go(Routes.landing) either.
/// Screens only call context.go for lateral moves a redirect cannot know
/// about (Landing -> Sign Up, the Sign Up <-> Log In footer links).
GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
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
      GoRoute(path: Routes.home, builder: (context, state) => const HomePage()),
    ],
  );
}
