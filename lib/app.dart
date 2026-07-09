import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'auth/bloc/auth_bloc.dart';
import 'auth/repository/auth_repository.dart';
import 'router/app_router.dart';
import 'theme/spotify_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<AuthRepository>.value(
      value: authRepository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(authRepository: context.read<AuthRepository>()),
          ),
        ],
        child: const AppView(),
      ),
    );
  }
}

/// Owns the GoRouter instance so the whole Navigator/route stack is never
/// torn down just because auth state changed -- only redirect re-runs,
/// driven by refreshListenable.
class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createRouter(context.read<AuthBloc>());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Spotify Clone',
      theme: SpotifyTheme.dark(),
      routerConfig: _router,
    );
  }
}
