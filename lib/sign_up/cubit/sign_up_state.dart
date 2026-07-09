import 'package:equatable/equatable.dart';

import '../../auth/validators/email_validator.dart';
import '../../auth/validators/password_validator.dart';

enum SignUpStatus { initial, submitting, success, failure }

class SignUpState extends Equatable {
  const SignUpState({
    this.email = '',
    this.password = '',
    this.confirmPassword = '',
    this.status = SignUpStatus.initial,
    this.errorMessage,
  });

  final String email;
  final String password;
  final String confirmPassword;
  final SignUpStatus status;
  final String? errorMessage;

  bool get isEmailValid => isValidEmail(email);
  bool get isPasswordValid => isValidPassword(password);
  bool get isConfirmPasswordValid => confirmPassword == password && password.isNotEmpty;
  bool get isValid => isEmailValid && isPasswordValid && isConfirmPasswordValid;

  /// errorMessage is intentionally NOT carried forward with `??` here: every
  /// field edit should clear a stale error, and a naive `?? this.errorMessage`
  /// could never express "clear this field" (the classic Dart copyWith trap).
  SignUpState copyWith({
    String? email,
    String? password,
    String? confirmPassword,
    SignUpStatus? status,
    String? errorMessage,
  }) {
    return SignUpState(
      email: email ?? this.email,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [email, password, confirmPassword, status, errorMessage];
}
