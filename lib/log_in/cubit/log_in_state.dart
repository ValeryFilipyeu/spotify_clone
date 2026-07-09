import 'package:equatable/equatable.dart';

import '../../auth/validators/email_validator.dart';
import '../../auth/validators/password_validator.dart';

enum LogInStatus { initial, submitting, success, failure }

class LogInState extends Equatable {
  const LogInState({
    this.email = '',
    this.password = '',
    this.status = LogInStatus.initial,
    this.errorMessage,
  });

  final String email;
  final String password;
  final LogInStatus status;
  final String? errorMessage;

  bool get isEmailValid => isValidEmail(email);
  bool get isPasswordValid => isValidPassword(password);
  bool get isValid => isEmailValid && isPasswordValid;

  LogInState copyWith({
    String? email,
    String? password,
    LogInStatus? status,
    String? errorMessage,
  }) {
    return LogInState(
      email: email ?? this.email,
      password: password ?? this.password,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [email, password, status, errorMessage];
}
