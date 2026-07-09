import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'auth/repository/fake_auth_repository.dart';
import 'auth/repository/session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authRepository = FakeAuthRepository(
    sessionStorage: const SecureSessionStorage(FlutterSecureStorage()),
  );
  await authRepository.restoreSession();

  runApp(MyApp(authRepository: authRepository));
}
