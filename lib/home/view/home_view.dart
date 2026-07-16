import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../router/app_routes.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/spotify_wordmark.dart';
import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';
import '../widgets/catalog_section_row.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SpotifyWordmark(fontSize: 18),
        actions: [
          // Logout still lives here so the auth flow stays reachable. No
          // navigation call -- dispatching the event flips AuthBloc to
          // unauthenticated and the router redirects to Landing on its own.
          IconButton(
            icon: const Icon(Icons.logout, color: SpotifyColors.textSecondary),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthBloc>().add(const AuthLogOutRequested()),
          ),
        ],
      ),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          switch (state.status) {
            case HomeStatus.initial:
            case HomeStatus.loading:
              return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
            case HomeStatus.failure:
              return _ErrorRetry(
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: () => context.read<HomeCubit>().loadSections(),
              );
            case HomeStatus.success:
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: state.sections.length,
                itemBuilder: (context, index) {
                  final section = state.sections[index];
                  return CatalogSectionRow(
                    section: section,
                    // push (not go) so the detail screen sits on top of Home
                    // and the back button returns here.
                    onItemTap: (itemId) => context.push(Routes.detailFor(itemId)),
                  );
                },
              );
          }
        },
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
