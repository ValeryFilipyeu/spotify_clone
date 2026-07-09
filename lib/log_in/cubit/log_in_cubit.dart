import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/auth_failure.dart';
import '../../auth/repository/auth_repository.dart';
import 'log_in_state.dart';

class LogInCubit extends Cubit<LogInState> {
  LogInCubit({required AuthRepository authRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _authRepository = authRepository,
        super(const LogInState());

  final AuthRepository _authRepository;

  void emailChanged(String value) {
    emit(state.copyWith(email: value, status: LogInStatus.initial));
  }

  void passwordChanged(String value) {
    emit(state.copyWith(password: value, status: LogInStatus.initial));
  }

  Future<void> submitted() async {
    if (!state.isValid) return;
    emit(state.copyWith(status: LogInStatus.submitting));
    try {
      await _authRepository.logIn(email: state.email, password: state.password);
      emit(state.copyWith(status: LogInStatus.success));
    } on LogInFailure catch (failure) {
      emit(state.copyWith(status: LogInStatus.failure, errorMessage: failure.message));
    }
  }
}
