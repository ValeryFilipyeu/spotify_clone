import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/spotify_primary_button.dart';
import '../../widgets/spotify_wordmark.dart';

/// Stateless, no Cubit -- there is nothing here for one to own.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              const Spacer(),
              const SpotifyWordmark(fontSize: 32),
              const SizedBox(height: 16),
              Text(
                'Your next favorite song is one tap away.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: SpotifyColors.textSecondary),
              ),
              const Spacer(),
              SpotifyPrimaryButton(
                label: 'Sign up free',
                onPressed: () => context.go(Routes.signUp),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.go(Routes.logIn),
                child: const Text('Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
