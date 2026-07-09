import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/auth_failure.dart';
import '../../auth/repository/auth_repository.dart';
import 'sign_up_state.dart';

/// Screen-local: owns form mechanics only. It never decides where the user
/// gets navigated to -- a successful signUp() flips AuthBloc to
/// authenticated and the router redirects to Home on its own.
class SignUpCubit extends Cubit<SignUpState> {
  SignUpCubit({required AuthRepository authRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _authRepository = authRepository,
        super(const SignUpState());

  final AuthRepository _authRepository;

  void emailChanged(String value) {
    emit(state.copyWith(email: value, status: SignUpStatus.initial));
  }

  void passwordChanged(String value) {
    emit(state.copyWith(password: value, status: SignUpStatus.initial));
  }

  void confirmPasswordChanged(String value) {
    emit(state.copyWith(confirmPassword: value, status: SignUpStatus.initial));
  }

  Future<void> submitted() async {
    if (!state.isValid) return;
    emit(state.copyWith(status: SignUpStatus.submitting));
    try {
      await _authRepository.signUp(email: state.email, password: state.password);
      emit(state.copyWith(status: SignUpStatus.success));
    } on SignUpFailure catch (failure) {
      emit(state.copyWith(status: SignUpStatus.failure, errorMessage: failure.message));
    }
  }
}
