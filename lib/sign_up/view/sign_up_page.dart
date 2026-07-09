import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/repository/auth_repository.dart';
import '../cubit/sign_up_cubit.dart';
import 'sign_up_view.dart';

class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SignUpCubit(authRepository: context.read<AuthRepository>()),
      child: const SignUpView(),
    );
  }
}
