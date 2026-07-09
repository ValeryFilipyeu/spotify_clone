import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/auth.dart';

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
  group('AuthBloc', () {
    test('initial state is unknown', () {
      final repository = FakeAuthRepository(sessionStorage: _InMemorySessionStorage());
      final bloc = AuthBloc(authRepository: repository);
      expect(bloc.state, const AuthState.unknown());
      bloc.close();
      repository.close();
    });

    test('reflects a repository signUp as authenticated, and logOut as unauthenticated', () async {
      final repository = FakeAuthRepository(sessionStorage: _InMemorySessionStorage());
      final bloc = AuthBloc(authRepository: repository);

      await repository.signUp(email: 'bloc@example.com', password: 'Password1');
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, const AuthState.authenticated(AppUser('bloc@example.com')));

      await repository.logOut();
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, const AuthState.unauthenticated());

      await bloc.close();
      await repository.close();
    });

    blocTest<AuthBloc, AuthState>(
      'AuthLogOutRequested results in an unauthenticated state',
      build: () => AuthBloc(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      act: (bloc) => bloc.add(const AuthLogOutRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.status, AuthStatus.unauthenticated),
    );
  });
}
