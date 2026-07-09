import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/auth.dart';
import 'package:spotify_clone/log_in/cubit/log_in_cubit.dart';
import 'package:spotify_clone/log_in/cubit/log_in_state.dart';

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
  group('LogInCubit', () {
    blocTest<LogInCubit, LogInState>(
      'emits submitting then success for the seeded demo account',
      build: () => LogInCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      seed: () => const LogInState(email: 'test@spotify.com', password: 'Password1'),
      act: (cubit) => cubit.submitted(),
      expect: () => [
        const LogInState(email: 'test@spotify.com', password: 'Password1', status: LogInStatus.submitting),
        const LogInState(email: 'test@spotify.com', password: 'Password1', status: LogInStatus.success),
      ],
    );

    blocTest<LogInCubit, LogInState>(
      'emits submitting then failure for the wrong password',
      build: () => LogInCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      seed: () => const LogInState(email: 'test@spotify.com', password: 'WrongPass1'),
      act: (cubit) => cubit.submitted(),
      expect: () => [
        const LogInState(email: 'test@spotify.com', password: 'WrongPass1', status: LogInStatus.submitting),
        const LogInState(
          email: 'test@spotify.com',
          password: 'WrongPass1',
          status: LogInStatus.failure,
          errorMessage: 'Incorrect password.',
        ),
      ],
    );

    blocTest<LogInCubit, LogInState>(
      'emits submitting then failure for an unknown email',
      build: () => LogInCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      seed: () => const LogInState(email: 'nobody@example.com', password: 'Password1'),
      act: (cubit) => cubit.submitted(),
      expect: () => [
        const LogInState(email: 'nobody@example.com', password: 'Password1', status: LogInStatus.submitting),
        const LogInState(
          email: 'nobody@example.com',
          password: 'Password1',
          status: LogInStatus.failure,
          errorMessage: 'No account found for that email.',
        ),
      ],
    );
  });
}
