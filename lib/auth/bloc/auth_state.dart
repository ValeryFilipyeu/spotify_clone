import 'package:equatable/equatable.dart';

import '../models/app_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// A single evolving state class, not a sealed hierarchy: authenticated and
/// unauthenticated share the same shape (a status plus an optional user) and
/// differ only in status, which is exactly the case where one class beats a
/// switch at every call site.
class AuthState extends Equatable {
  const AuthState._({this.status = AuthStatus.unknown, this.user});

  /// Before the repository's first value has arrived (a brief window on
  /// cold boot) -- never "authenticating", just "do not know yet".
  const AuthState.unknown() : this._();

  const AuthState.authenticated(AppUser user) : this._(status: AuthStatus.authenticated, user: user);

  const AuthState.unauthenticated() : this._(status: AuthStatus.unauthenticated);

  final AuthStatus status;
  final AppUser? user;

  @override
  List<Object?> get props => [status, user];
}
