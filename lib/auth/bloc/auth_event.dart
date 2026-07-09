import 'package:equatable/equatable.dart';

import '../models/app_user.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched internally by [AuthBloc] itself as it re-broadcasts every value
/// from AuthRepository.authStateChanges -- never dispatched by a screen.
class AuthUserChanged extends AuthEvent {
  const AuthUserChanged(this.user);

  final AppUser? user;

  @override
  List<Object?> get props => [user];
}

class AuthLogOutRequested extends AuthEvent {
  const AuthLogOutRequested();
}
