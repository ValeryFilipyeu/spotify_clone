import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'auth/bloc/auth_bloc.dart';
import 'auth/bloc/auth_state.dart';
import 'auth/repository/auth_repository.dart';
import 'catalog/repository/catalog_repository.dart';
import 'catalog/repository/fake_catalog_repository.dart';
import 'catalog/images/cover_image_scope.dart';
import 'catalog/repository/offline/offline_status.dart';
import 'history/cubit/play_history_cubit.dart';
import 'history/repository/play_history_repository.dart';
import 'likes/cubit/likes_cubit.dart';
import 'likes/repository/likes_repository.dart';
import 'player/audio/audio_controller.dart';
import 'player/bloc/player_bloc.dart';
import 'player/bloc/player_event.dart';
import 'player/repository/playback_queue_repository.dart';
import 'player/repository/playback_settings_repository.dart';
import 'player/session/media_session.dart';
import 'player/session/playback_audio_session.dart';
import 'router/app_router.dart';
import 'storage/image_byte_store.dart';
import 'theme/spotify_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.authRepository,
    required this.likesRepository,
    required this.playHistoryRepository,
    required this.playbackSettingsRepository,
    this.playbackQueueRepository,
    required this.audioController,
    this.catalogRepository,
    this.offlineStatus = const AlwaysOnline(),
    this.coverImageStore,
    this.mediaSession,
    this.audioSession,
  });

  final AuthRepository authRepository;

  /// Injected so tests can supply an in-memory store.
  final LikesRepository likesRepository;

  /// Backs Home's "Recently played" row.
  final PlayHistoryRepository playHistoryRepository;

  /// Per-account playback preferences.
  final PlaybackSettingsRepository playbackSettingsRepository;

  /// Where the queue is left between launches. Without it the player forgets
  /// everything on close, which is what widget tests want.
  final PlaybackQueueRepository? playbackQueueRepository;

  /// Injected so widget tests never touch just_audio's platform channels.
  final AudioController audioController;

  /// main() supplies the live one; null falls back to [FakeCatalogRepository],
  /// which is what widget tests want.
  final CatalogRepository? catalogRepository;

  /// Whether the catalog is answering from the network or from disk. The same
  /// object as [catalogRepository] in main(): the layer that discovers it is the
  /// layer that falls back.
  ///
  /// Defaulted rather than nullable -- [AlwaysOnline] is an honest answer, so
  /// nothing downstream handles an absent status.
  final OfflineStatus offlineStatus;

  /// Where covers are kept. Null on the web (the browser caches them already)
  /// and in widget tests; both then fetch every time.
  final ImageByteStore? coverImageStore;

  /// Lock screen, notification, headset buttons. Null in widget tests.
  final MediaSession? mediaSession;

  /// Calls and nav prompts taking the speaker, and headphones unplugged.
  final PlaybackAudioSession? audioSession;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        // The single composition point that names a concrete implementation.
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<LikesRepository>.value(value: likesRepository),
        RepositoryProvider<PlayHistoryRepository>.value(value: playHistoryRepository),
        RepositoryProvider<PlaybackSettingsRepository>.value(value: playbackSettingsRepository),
        if (playbackQueueRepository case final queue?)
          RepositoryProvider<PlaybackQueueRepository>.value(value: queue),
        RepositoryProvider<CatalogRepository>(
          create: (_) => catalogRepository ?? const FakeCatalogRepository(),
        ),
        RepositoryProvider<OfflineStatus>.value(value: offlineStatus),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(authRepository: context.read<AuthRepository>()),
          ),
          BlocProvider<PlayerBloc>(
            create: (context) => PlayerBloc(
              audioController: audioController,
              settingsRepository: context.read<PlaybackSettingsRepository>(),
              queueRepository: playbackQueueRepository,
              // The player needs which account, not anything else about them.
              userIdChanges: context.read<AuthRepository>().authStateChanges.map(
                (user) => user?.email,
              ),
              mediaSession: mediaSession,
              audioSession: audioSession,
            ),
          ),
          // App-wide so a heart tapped anywhere is reflected everywhere.
          BlocProvider<LikesCubit>(
            create: (context) => LikesCubit(
              repository: context.read<LikesRepository>(),
              authStateChanges: context.read<AuthRepository>().authStateChanges,
              // For writing, not reading: see LikesCubit._keepForOffline.
              catalogRepository: context.read<CatalogRepository>(),
            ),
          ),
          // App-wide: playback starts from several screens and Home sees all.
          BlocProvider<PlayHistoryCubit>(
            create: (context) => PlayHistoryCubit(
              repository: context.read<PlayHistoryRepository>(),
              authStateChanges: context.read<AuthRepository>().authStateChanges,
            ),
          ),
        ],
        // Above the router, so every screen's covers share one cache.
        child: CoverImageScope(store: coverImageStore, child: const AppView()),
      ),
    );
  }
}

/// Owns the GoRouter instance, so an auth change re-runs redirect rather than
/// tearing down the whole Navigator stack.
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
      // The mini-player lives in the tab shell's chrome (ScaffoldWithNavBar),
      // which keeps it out of the auth screens and under the Now Playing route.
      child: MaterialApp.router(
        title: 'Spotify Clone',
        theme: SpotifyTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
