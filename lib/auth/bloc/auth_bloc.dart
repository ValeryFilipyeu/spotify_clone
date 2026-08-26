import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../repository/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// The app-wide source of truth for "am I logged in". Knows nothing about form
/// fields, and decides no navigation -- the router reacts to this state.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository authRepository})
    // ignore: prefer_initializing_formals -- keeps the public param name.
    : _authRepository = authRepository,
      super(const AuthState.unknown()) {
    on<AuthUserChanged>(_onUserChanged);
    on<AuthLogOutRequested>(_onLogOutRequested);
    _userSubscription = _authRepository.authStateChanges.listen(
      (user) => add(AuthUserChanged(user)),
    );
  }

  final AuthRepository _authRepository;
  late final StreamSubscription<dynamic> _userSubscription;

  void _onUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    emit(
      event.user == null ? const AuthState.unauthenticated() : AuthState.authenticated(event.user!),
    );
  }

  Future<void> _onLogOutRequested(AuthLogOutRequested event, Emitter<AuthState> emit) {
    // No emit: logOut() pushes null through authStateChanges, so one code path
    // produces every auth transition.
    return _authRepository.logOut();
  }

  @override
  Future<void> close() {
    _userSubscription.cancel();
    return super.close();
  }
}
