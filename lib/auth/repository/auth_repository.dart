import '../models/app_user.dart';

/// The one seam a real backend (Firebase, a REST API, ...) would plug into
/// later. Nothing outside lib/auth/repository/ and main.dart's composition
/// point may reference a concrete implementation of this interface.
abstract class AuthRepository {
  /// Emits the current user immediately to every new subscriber, then every
  /// subsequent change. Emits `null` when signed out.
  Stream<AppUser?> get authStateChanges;

  Future<void> signUp({required String email, required String password});

  Future<void> logIn({required String email, required String password});

  Future<void> logOut();
}
