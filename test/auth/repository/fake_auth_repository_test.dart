import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/auth/models/auth_failure.dart';
import 'package:spotify_clone/auth/repository/fake_auth_repository.dart';
import 'package:spotify_clone/auth/repository/session_storage.dart';

/// A pure in-memory SessionStorage so these tests never touch a real
/// platform channel.
class _InMemorySessionStorage implements SessionStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

void main() {
  late FakeAuthRepository repository;

  setUp(() {
    repository = FakeAuthRepository(sessionStorage: _InMemorySessionStorage());
  });

  tearDown(() => repository.close());

  group('FakeAuthRepository', () {
    test('the seeded demo account can log in', () async {
      await repository.logIn(email: 'test@spotify.com', password: 'Password1');
    });

    test('logIn throws for an email with no account', () async {
      expect(
        () => repository.logIn(email: 'nobody@spotify.com', password: 'whatever1'),
        throwsA(isA<LogInFailure>()),
      );
    });

    test('logIn throws for the wrong password', () async {
      expect(
        () => repository.logIn(email: 'test@spotify.com', password: 'wrong-password'),
        throwsA(isA<LogInFailure>()),
      );
    });

    test('signUp succeeds for a new email and normalizes case', () async {
      await repository.signUp(email: 'New.User@Example.com', password: 'Password1');
      await repository.logIn(email: 'new.user@example.com', password: 'Password1');
    });

    test('signUp throws when the email is already registered', () async {
      await repository.signUp(email: 'dup@example.com', password: 'Password1');
      expect(
        () => repository.signUp(email: 'dup@example.com', password: 'Password2'),
        throwsA(isA<SignUpFailure>()),
      );
    });

    test('authStateChanges replays the current user then emits on signUp/logOut', () async {
      final emitted = <AppUser?>[];
      final subscription = repository.authStateChanges.listen(emitted.add);

      await repository.signUp(email: 'stream@example.com', password: 'Password1');
      await repository.logOut();
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [
        null,
        const AppUser('stream@example.com'),
        null,
      ]);

      await subscription.cancel();
    });
  });
}
