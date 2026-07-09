import 'dart:async';
import 'dart:convert';

import '../models/app_user.dart';
import '../models/auth_failure.dart';
import 'auth_repository.dart';
import 'session_storage.dart';

/// An in-memory stand-in for a real backend. Every method's success/failure
/// behavior is fully deterministic, which is what lets it double as its own
/// test double (see test/auth/repository/fake_auth_repository_test.dart and
/// test/auth/bloc/auth_bloc_test.dart) with no mocking package required.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({required SessionStorage sessionStorage})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _sessionStorage = sessionStorage {
    // Seeded so Log In is usable on a fresh install with no prior Sign Up.
    _users[_demoEmail] = _demoPassword;
  }

  static const _demoEmail = 'test@spotify.com';
  static const _demoPassword = 'Password1';
  static const _sessionEmailKey = 'auth_session_email';
  static const _accountsKey = 'auth_accounts';

  final SessionStorage _sessionStorage;
  final Map<String, String> _users = {};
  final StreamController<AppUser?> _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  @override
  Stream<AppUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  /// Rehydrates any persisted accounts/session. Not part of [AuthRepository]
  /// -- it is a bootstrap detail specific to this fake implementation, called
  /// once from main() before runApp.
  Future<void> restoreSession() async {
    final accountsJson = await _sessionStorage.read(_accountsKey);
    if (accountsJson != null) {
      final decoded = jsonDecode(accountsJson) as Map<String, dynamic>;
      _users.addAll(decoded.map((key, value) => MapEntry(key, value as String)));
    }
    final sessionEmail = await _sessionStorage.read(_sessionEmailKey);
    if (sessionEmail != null && _users.containsKey(sessionEmail)) {
      _currentUser = AppUser(sessionEmail);
    }
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    final normalized = _normalize(email);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_users.containsKey(normalized)) {
      throw const SignUpFailure('An account with that email already exists.');
    }
    _users[normalized] = password;
    await _persistAccounts();
    await _sessionStorage.write(_sessionEmailKey, normalized);
    _currentUser = AppUser(normalized);
    _controller.add(_currentUser);
  }

  @override
  Future<void> logIn({required String email, required String password}) async {
    final normalized = _normalize(email);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final storedPassword = _users[normalized];
    if (storedPassword == null) {
      throw const LogInFailure('No account found for that email.');
    }
    if (storedPassword != password) {
      throw const LogInFailure('Incorrect password.');
    }
    await _sessionStorage.write(_sessionEmailKey, normalized);
    _currentUser = AppUser(normalized);
    _controller.add(_currentUser);
  }

  @override
  Future<void> logOut() async {
    await _sessionStorage.delete(_sessionEmailKey);
    _currentUser = null;
    _controller.add(null);
  }

  Future<void> _persistAccounts() => _sessionStorage.write(_accountsKey, jsonEncode(_users));

  String _normalize(String email) => email.trim().toLowerCase();

  /// Not part of [AuthRepository] -- only used to tear the fake down between
  /// tests, never in production, since the repository is a process-lifetime
  /// singleton there.
  Future<void> close() => _controller.close();
}
