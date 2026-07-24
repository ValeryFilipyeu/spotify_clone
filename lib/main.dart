import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'auth/repository/fake_auth_repository.dart';
import 'auth/repository/session_storage.dart';
import 'likes/repository/local_likes_repository.dart';
import 'player/audio/just_audio_controller.dart';
import 'storage/key_value_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Non-sensitive local state (likes) lives in shared_preferences, kept
  // separate from the Keychain-backed auth session above. The instance is
  // fetched once here and injected, so no call site awaits a platform channel.
  final prefs = await SharedPreferences.getInstance();
  final likesRepository = LocalLikesRepository(SharedPreferencesStore(prefs));

  runApp(
    MyApp(
      authRepository: authRepository,
      likesRepository: likesRepository,
      audioController: JustAudioController(),
    ),
  );
}
