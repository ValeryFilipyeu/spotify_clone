import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'auth/repository/fake_auth_repository.dart';
import 'auth/repository/session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authRepository = FakeAuthRepository(
    sessionStorage: SecureSessionStorage(
      FlutterSecureStorage(
        // macOS defaults to kSecUseDataProtectionKeychain, which validates
        // the app's Keychain access group against a real Apple Developer
        // Team ID -- this project is signed ad-hoc (no team), so that check
        // fails with errSecMissingEntitlement (-34018). The legacy Keychain
        // API below doesn't require that validation.
        mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
      ),
    ),
  );
  await authRepository.restoreSession();

  runApp(MyApp(authRepository: authRepository));
}
