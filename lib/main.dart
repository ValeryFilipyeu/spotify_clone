import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'auth/repository/fake_auth_repository.dart';
import 'auth/repository/session_storage.dart';
import 'catalog/repository/audius/audius_catalog_repository.dart';
import 'catalog/repository/offline/catalog_cache_store.dart';
import 'catalog/repository/offline/offline_catalog_repository.dart';
import 'history/repository/local_play_history_repository.dart';
import 'likes/repository/local_likes_repository.dart';
import 'player/audio/crossfade_audio_controller.dart';
import 'player/audio/just_audio_controller.dart';
import 'player/repository/local_playback_settings_repository.dart';
import 'player/session/audio_service_media_session.dart';
import 'player/session/platform_audio_session.dart';
import 'network/api_client.dart';
import 'storage/key_value_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Registers the app with the OS media session: this is what keeps audio alive
  // once the app is backgrounded and what draws the lock-screen / notification
  // controls. Must happen before runApp -- on Android it binds a foreground
  // service, and audio_service owns the FlutterEngine the service attaches to.
  final mediaSession = await AudioService.init(
    builder: AudioServiceMediaSession.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.valery.spotify_clone.playback',
      androidNotificationChannelName: 'Playback',
      // Keep the notification while paused, the way real music apps do. It also
      // sidesteps Android 12's ForegroundServiceStartNotAllowedException: with
      // `true` the service leaves the foreground on pause and may then be
      // refused permission to re-enter it when the user hits play again.
      androidStopForegroundOnPause: false,
      androidNotificationOngoing: false,
    ),
  );

  final authRepository = FakeAuthRepository(
    sessionStorage: SecureSessionStorage(
      FlutterSecureStorage(
        // macOS defaults to the Data Protection Keychain, which needs a
        // keychain-access-group entitlement tied to a real Apple Developer
        // Team ID -- this project is signed ad-hoc (no team), so that check
        // fails with errSecMissingEntitlement (-34018). The legacy Keychain
        // API below doesn't require it. macOS-only; iOS/Android/web unaffected.
        mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
      ),
    ),
  );
  await authRepository.restoreSession();

  // Non-sensitive local state (likes, playback preferences) lives in
  // shared_preferences, kept separate from the Keychain-backed auth session
  // above. The instance is fetched once here and injected, so no call site
  // awaits a platform channel.
  final prefs = await SharedPreferences.getInstance();
  final keyValueStore = SharedPreferencesStore(prefs);

  // The real catalog, assembled here and nowhere else. Three layers, each of
  // which the one below knows nothing about:
  //
  //   offline  -- keeps answers on the device and serves them when the network
  //               cannot be reached, and reports which of those is happening
  //   caching  -- remembers answers for five minutes, so moving around the app
  //               is free
  //   audius   -- a plain translation of an HTTP API
  //
  // One long-lived ApiClient underneath, so its connection pool and its
  // in-flight de-duplication are shared: Home builds several rows at once, and
  // the same url wanted twice is one round trip.
  //
  // The order is not incidental and is therefore not written here: `chain` owns
  // it, so that the reason for it and a test of it live together. See
  // OfflineCatalogRepository.chain.
  //
  // The fake used by tests is deliberately left unwrapped by any of this, so
  // they see every call.
  final catalogRepository = OfflineCatalogRepository.chain(
    AudiusCatalogRepository(
      client: ApiClient(
        baseUrl: AudiusCatalogRepository.baseUrl,
        defaultQuery: const {'app_name': AudiusCatalogRepository.appName},
      ),
    ),
    store: CatalogCacheStore(keyValueStore),
  );

  runApp(
    MyApp(
      authRepository: authRepository,
      catalogRepository: catalogRepository,
      // The same object: the layer that discovers it is the layer that falls
      // back to the saved copy.
      offlineStatus: catalogRepository,
      likesRepository: LocalLikesRepository(keyValueStore),
      playHistoryRepository: LocalPlayHistoryRepository(keyValueStore),
      playbackSettingsRepository: LocalPlaybackSettingsRepository(keyValueStore),
      // Two engines behind one seam, so a track can fade out while the next
      // fades in. With crossfade off (the default) only one of them is ever
      // used, so this costs nothing until the setting is turned up.
      audioController: CrossfadeAudioController(createPlayer: JustAudioController.new),
      mediaSession: mediaSession,
      // Configures and claims the audio session -- nothing else in the stack
      // does (see PlatformAudioSession). Created after AudioService.init because
      // audio_session's docs say to apply your configuration last, once every
      // other audio plugin has loaded.
      audioSession: await PlatformAudioSession.create(),
    ),
  );
}
