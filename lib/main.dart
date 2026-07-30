import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'auth/repository/fake_auth_repository.dart';
import 'auth/repository/session_storage.dart';
import 'likes/repository/local_likes_repository.dart';
import 'player/audio/crossfade_audio_controller.dart';
import 'player/audio/just_audio_controller.dart';
import 'player/repository/local_playback_settings_repository.dart';
import 'player/session/audio_service_media_session.dart';
import 'player/session/platform_audio_session.dart';
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

  runApp(
    MyApp(
      authRepository: authRepository,
      likesRepository: LocalLikesRepository(keyValueStore),
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
