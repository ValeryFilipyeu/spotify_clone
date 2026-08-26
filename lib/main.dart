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
import 'player/audio/audio_cache.dart';
import 'player/audio/crossfade_audio_controller.dart';
import 'player/audio/just_audio_controller.dart';
import 'player/repository/local_playback_queue_repository.dart';
import 'player/repository/local_playback_settings_repository.dart';
import 'player/session/audio_service_media_session.dart';
import 'player/session/platform_audio_session.dart';
import 'network/api_client.dart';
import 'storage/image_byte_store.dart';
import 'storage/key_value_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keeps audio alive in the background and draws the lock-screen controls.
  // Before runApp: on Android this binds a foreground service, and audio_service
  // owns the FlutterEngine it attaches to.
  final mediaSession = await AudioService.init(
    builder: AudioServiceMediaSession.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.valery.spotify_clone.playback',
      androidNotificationChannelName: 'Playback',
      // Keeps the notification while paused, and sidesteps Android 12's
      // ForegroundServiceStartNotAllowedException on the next play.
      androidStopForegroundOnPause: false,
      androidNotificationOngoing: false,
    ),
  );

  final authRepository = FakeAuthRepository(
    sessionStorage: SecureSessionStorage(
      FlutterSecureStorage(
        // The Data Protection Keychain needs an entitlement tied to a real
        // Team ID, and this project is signed ad-hoc -- errSecMissingEntitlement
        // (-34018). macOS only; the legacy API has no such check.
        mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
      ),
    ),
  );
  await authRepository.restoreSession();

  // Non-sensitive local state, kept out of the Keychain. Fetched once and
  // injected, so no call site awaits a platform channel.
  final prefs = await SharedPreferences.getInstance();
  final keyValueStore = SharedPreferencesStore(prefs);

  // Three layers: offline (disk fallback + status), caching (5 min in memory),
  // audius (the HTTP API). The order is owned by `chain`, not written here.
  //
  // One long-lived ApiClient underneath, so its pool and its in-flight
  // de-duplication are shared across all of them.
  final catalogRepository = OfflineCatalogRepository.chain(
    AudiusCatalogRepository(
      client: ApiClient(
        baseUrl: AudiusCatalogRepository.baseUrl,
        defaultQuery: const {'app_name': AudiusCatalogRepository.appName},
      ),
    ),
    store: CatalogCacheStore(keyValueStore),
  );

  // Before runApp, so the first frame's covers can come off disk. Null on the
  // web; see openImageByteStore.
  final coverImageStore = await openImageByteStore();

  // Shared by both crossfade players: a track one finished is a file the other
  // can open.
  final audioCache = await openAudioCache();

  runApp(
    MyApp(
      authRepository: authRepository,
      catalogRepository: catalogRepository,
      // The same object: whoever falls back is whoever knows.
      offlineStatus: catalogRepository,
      coverImageStore: coverImageStore,
      likesRepository: LocalLikesRepository(keyValueStore),
      playHistoryRepository: LocalPlayHistoryRepository(keyValueStore),
      playbackSettingsRepository: LocalPlaybackSettingsRepository(keyValueStore),
      playbackQueueRepository: LocalPlaybackQueueRepository(keyValueStore),
      // Two engines behind one seam. With crossfade off (the default) only one
      // is ever used, so it costs nothing until the setting is turned up.
      audioController: CrossfadeAudioController(
        createPlayer: () => JustAudioController(audioCache: audioCache),
      ),
      mediaSession: mediaSession,
      // After AudioService.init: audio_session's configuration has to be applied
      // once every other audio plugin has loaded.
      audioSession: await PlatformAudioSession.create(),
    ),
  );
}
