import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../widgets/spotify_primary_button.dart';
import '../../widgets/spotify_text_field.dart';
import '../cubit/log_in_cubit.dart';
import '../cubit/log_in_state.dart';

class LogInView extends StatelessWidget {
  const LogInView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<LogInCubit, LogInState>(
      listenWhen: (previous, current) => current.status == LogInStatus.failure,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage ?? 'Something went wrong.')),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Log in')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Log in to Spotify Clone.', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Demo account: test@spotify.com / Password1',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                BlocBuilder<LogInCubit, LogInState>(
                  buildWhen: (previous, current) =>
                      previous.email != current.email || previous.status != current.status,
                  builder: (context, state) {
                    return SpotifyTextField(
                      labelText: 'Email address',
                      keyboardType: TextInputType.emailAddress,
                      enabled: state.status != LogInStatus.submitting,
                      errorText: state.email.isEmpty || state.isEmailValid ? null : 'Enter a valid email address.',
                      onChanged: context.read<LogInCubit>().emailChanged,
                    );
                  },
                ),
                const SizedBox(height: 16),
                BlocBuilder<LogInCubit, LogInState>(
                  buildWhen: (previous, current) =>
                      previous.password != current.password || previous.status != current.status,
                  builder: (context, state) {
                    return SpotifyTextField(
                      labelText: 'Password',
                      obscureText: true,
                      enabled: state.status != LogInStatus.submitting,
                      errorText: state.password.isEmpty || state.isPasswordValid
                          ? null
                          : 'Password must be 8+ characters with a number.',
                      onChanged: context.read<LogInCubit>().passwordChanged,
                    );
                  },
                ),
                const SizedBox(height: 32),
                BlocBuilder<LogInCubit, LogInState>(
                  builder: (context, state) {
                    return SpotifyPrimaryButton(
                      label: 'Log in',
                      isLoading: state.status == LogInStatus.submitting,
                      onPressed: state.isValid ? context.read<LogInCubit>().submitted : null,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => context.go(Routes.signUp),
                    child: const Text("Don't have an account? Sign up"),
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
