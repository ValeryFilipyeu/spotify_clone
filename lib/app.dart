import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'auth/bloc/auth_bloc.dart';
import 'auth/bloc/auth_state.dart';
import 'auth/repository/auth_repository.dart';
import 'catalog/repository/catalog_repository.dart';
import 'catalog/repository/fake_catalog_repository.dart';
import 'likes/cubit/likes_cubit.dart';
import 'likes/repository/likes_repository.dart';
import 'player/audio/audio_controller.dart';
import 'player/bloc/player_bloc.dart';
import 'player/bloc/player_event.dart';
import 'router/app_router.dart';
import 'theme/spotify_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.authRepository,
    required this.likesRepository,
    required this.audioController,
  });

  final AuthRepository authRepository;

  /// Injected like [authRepository] so tests can supply an in-memory store
  /// instead of touching shared_preferences' platform channel.
  final LikesRepository likesRepository;

  /// Injected (not created here) so widget tests can pass a fake and never
  /// touch just_audio's platform channels -- same reason authRepository is
  /// injected.
  final AudioController audioController;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        // Auth is provided by value: it was built and async-restored in
        // main() before runApp. Catalog needs no bootstrap, so it is created
        // lazily here -- still the single composition point that names the
        // concrete fake.
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<LikesRepository>.value(value: likesRepository),
        RepositoryProvider<CatalogRepository>(create: (_) => const FakeCatalogRepository()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(authRepository: context.read<AuthRepository>()),
          ),
          BlocProvider<PlayerBloc>(
            create: (context) => PlayerBloc(audioController: audioController),
          ),
          // App-wide so a heart tapped on any screen is reflected everywhere.
          // Follows the auth stream: loads the signed-in account's likes and
          // clears them on logout (likes are per-account).
          BlocProvider<LikesCubit>(
            create: (context) => LikesCubit(
              repository: context.read<LikesRepository>(),
              authStateChanges: context.read<AuthRepository>().authStateChanges,
            ),
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
    return BlocListener<AuthBloc, AuthState>(
      // Stop playback and clear the queue when the user logs out.
      listenWhen: (previous, current) => current.status == AuthStatus.unauthenticated,
      listener: (context, state) => context.read<PlayerBloc>().add(const PlayerStopped()),
      // The mini-player is no longer injected here: it's part of the tab
      // shell's chrome now (see ScaffoldWithNavBar), sitting above the bottom
      // navigation bar. That keeps it inside the authenticated shell and out of
      // the auth screens, and it's automatically hidden under the full-screen
      // "Now Playing" route (which covers the shell).
      child: MaterialApp.router(
        title: 'Spotify Clone',
        theme: SpotifyTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
