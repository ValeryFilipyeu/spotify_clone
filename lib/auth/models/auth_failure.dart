/// Thrown by [AuthRepository.signUp] when the email is already registered.
class SignUpFailure implements Exception {
  const SignUpFailure(this.message);

  final String message;
}

/// Thrown by [AuthRepository.logIn] when the account does not exist or the
/// password does not match.
class LogInFailure implements Exception {
  const LogInFailure(this.message);

  final String message;
}
