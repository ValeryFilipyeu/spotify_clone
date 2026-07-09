import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/repository/auth_repository.dart';
import '../cubit/log_in_cubit.dart';
import 'log_in_view.dart';

class LogInPage extends StatelessWidget {
  const LogInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LogInCubit(authRepository: context.read<AuthRepository>()),
      child: const LogInView(),
    );
  }
}
