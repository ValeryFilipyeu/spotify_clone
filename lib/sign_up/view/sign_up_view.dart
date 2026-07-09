import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../widgets/spotify_primary_button.dart';
import '../../widgets/spotify_text_field.dart';
import '../cubit/sign_up_cubit.dart';
import '../cubit/sign_up_state.dart';

class SignUpView extends StatelessWidget {
  const SignUpView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SignUpCubit, SignUpState>(
      listenWhen: (previous, current) => current.status == SignUpStatus.failure,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage ?? 'Something went wrong.')),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Sign up')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sign up to start listening.', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 32),
                BlocBuilder<SignUpCubit, SignUpState>(
                  buildWhen: (previous, current) =>
                      previous.email != current.email || previous.status != current.status,
                  builder: (context, state) {
                    return SpotifyTextField(
                      labelText: 'Email address',
                      keyboardType: TextInputType.emailAddress,
                      enabled: state.status != SignUpStatus.submitting,
                      errorText: state.email.isEmpty || state.isEmailValid ? null : 'Enter a valid email address.',
                      onChanged: context.read<SignUpCubit>().emailChanged,
                    );
                  },
                ),
                const SizedBox(height: 16),
                BlocBuilder<SignUpCubit, SignUpState>(
                  buildWhen: (previous, current) =>
                      previous.password != current.password || previous.status != current.status,
                  builder: (context, state) {
                    return SpotifyTextField(
                      labelText: 'Password',
                      obscureText: true,
                      enabled: state.status != SignUpStatus.submitting,
                      helperText: '8+ characters, at least one number',
                      errorText: state.password.isEmpty || state.isPasswordValid
                          ? null
                          : 'Password must be 8+ characters with a number.',
                      onChanged: context.read<SignUpCubit>().passwordChanged,
                    );
                  },
                ),
                const SizedBox(height: 16),
                BlocBuilder<SignUpCubit, SignUpState>(
                  buildWhen: (previous, current) =>
                      previous.confirmPassword != current.confirmPassword ||
                      previous.password != current.password ||
                      previous.status != current.status,
                  builder: (context, state) {
                    return SpotifyTextField(
                      labelText: 'Confirm password',
                      obscureText: true,
                      enabled: state.status != SignUpStatus.submitting,
                      errorText:
                          state.confirmPassword.isEmpty || state.isConfirmPasswordValid ? null : 'Passwords do not match.',
                      onChanged: context.read<SignUpCubit>().confirmPasswordChanged,
                    );
                  },
                ),
                const SizedBox(height: 32),
                BlocBuilder<SignUpCubit, SignUpState>(
                  builder: (context, state) {
                    return SpotifyPrimaryButton(
                      label: 'Sign up',
                      isLoading: state.status == SignUpStatus.submitting,
                      onPressed: state.isValid ? context.read<SignUpCubit>().submitted : null,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => context.go(Routes.logIn),
                    child: const Text('Already have an account? Log in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
