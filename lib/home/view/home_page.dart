import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/spotify_wordmark.dart';

/// A minimal placeholder proving successful post-auth navigation -- real
/// Home/Search/Player/Library features are out of scope for this step.
/// Stateless, no Cubit of its own: it only reads the app-wide AuthBloc.
///
/// Note there is no navigation call anywhere in this widget. Logging out
/// flips AuthBloc to unauthenticated, and the router's redirect sends the
/// user back to Landing on its own -- this is the clearest demonstration in
/// the whole feature that navigation is a pure side effect of auth state,
/// never something a screen decides for itself.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;

    return Scaffold(
      appBar: AppBar(title: const SpotifyWordmark(fontSize: 18)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Logged in as', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: SpotifyColors.textSecondary)),
            const SizedBox(height: 4),
            Text(user?.email ?? '', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => context.read<AuthBloc>().add(const AuthLogOutRequested()),
              child: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}
