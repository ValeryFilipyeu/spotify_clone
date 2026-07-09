import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/auth.dart';
import 'package:spotify_clone/sign_up/cubit/sign_up_cubit.dart';
import 'package:spotify_clone/sign_up/cubit/sign_up_state.dart';

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
  group('SignUpCubit', () {
    blocTest<SignUpCubit, SignUpState>(
      'field changes update state and clear a stale status',
      build: () => SignUpCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      act: (cubit) {
        cubit.emailChanged('new@example.com');
        cubit.passwordChanged('Password1');
        cubit.confirmPasswordChanged('Password1');
      },
      expect: () => [
        const SignUpState(email: 'new@example.com'),
        const SignUpState(email: 'new@example.com', password: 'Password1'),
        const SignUpState(email: 'new@example.com', password: 'Password1', confirmPassword: 'Password1'),
      ],
    );

    blocTest<SignUpCubit, SignUpState>(
      'submitted() does nothing while the form is invalid',
      build: () => SignUpCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      act: (cubit) => cubit.submitted(),
      expect: () => <SignUpState>[],
    );

    blocTest<SignUpCubit, SignUpState>(
      'emits submitting then success for a new valid email',
      build: () => SignUpCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      seed: () => const SignUpState(email: 'new@example.com', password: 'Password1', confirmPassword: 'Password1'),
      act: (cubit) => cubit.submitted(),
      expect: () => [
        const SignUpState(
          email: 'new@example.com',
          password: 'Password1',
          confirmPassword: 'Password1',
          status: SignUpStatus.submitting,
        ),
        const SignUpState(
          email: 'new@example.com',
          password: 'Password1',
          confirmPassword: 'Password1',
          status: SignUpStatus.success,
        ),
      ],
    );

    blocTest<SignUpCubit, SignUpState>(
      'emits submitting then failure when the email is already registered',
      build: () => SignUpCubit(authRepository: FakeAuthRepository(sessionStorage: _InMemorySessionStorage())),
      seed: () => const SignUpState(email: 'test@spotify.com', password: 'Password1', confirmPassword: 'Password1'),
      act: (cubit) => cubit.submitted(),
      expect: () => [
        const SignUpState(
          email: 'test@spotify.com',
          password: 'Password1',
          confirmPassword: 'Password1',
          status: SignUpStatus.submitting,
        ),
        const SignUpState(
          email: 'test@spotify.com',
          password: 'Password1',
          confirmPassword: 'Password1',
          status: SignUpStatus.failure,
          errorMessage: 'An account with that email already exists.',
        ),
      ],
    );
  });
}
