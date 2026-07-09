import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../repository/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// App-wide, one instance for the whole app lifetime: the single source of
/// truth for "am I logged in", which the router and any future app-wide
/// widget (a persistent mini-player, say) can all react to. It never knows
/// about form fields -- that is SignUpCubit/LogInCubit's job -- and it never
/// decides where the user gets navigated to -- that is the router's job,
/// driven by this bloc's state.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository authRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _authRepository = authRepository,
        super(const AuthState.unknown()) {
    on<AuthUserChanged>(_onUserChanged);
    on<AuthLogOutRequested>(_onLogOutRequested);
    _userSubscription = _authRepository.authStateChanges.listen((user) => add(AuthUserChanged(user)));
  }

  final AuthRepository _authRepository;
  late final StreamSubscription<dynamic> _userSubscription;

  void _onUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    emit(event.user == null ? const AuthState.unauthenticated() : AuthState.authenticated(event.user!));
  }

  Future<void> _onLogOutRequested(AuthLogOutRequested event, Emitter<AuthState> emit) {
    // No emit here: logOut() pushes null through authStateChanges, which
    // _onUserChanged turns into the unauthenticated state. One code path
    // produces every authenticated/unauthenticated transition.
    return _authRepository.logOut();
  }

  @override
  Future<void> close() {
    _userSubscription.cancel();
    return super.close();
  }
}
