import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../history/cubit/play_history_cubit.dart';
import '../../history/cubit/play_history_state.dart';
import '../../router/app_routes.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/refresh_feedback.dart';
import '../../widgets/spotify_wordmark.dart';
import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';
import '../greeting.dart';
import '../widgets/catalog_section_row.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SpotifyWordmark(fontSize: 18),
        actions: [
          // No navigation call: the event flips AuthBloc and the router
          // redirects on its own.
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
              return const Center(
                child: CircularProgressIndicator(
                  color: SpotifyColors.green,
                  semanticsLabel: 'Loading',
                ),
              );
            case HomeStatus.failure:
              return ErrorRetry(
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: () => context.read<HomeCubit>().loadSections(
                  context.read<PlayHistoryCubit>().state.recentIds,
                ),
              );
            case HomeStatus.success:
              // The catalog comes from one cubit and the personalisation from
              // another; this is where they meet. Playing anything in the app
              // reorders Home with no reload.
              return BlocConsumer<PlayHistoryCubit, PlayHistoryState>(
                // History may name items no row here contains -- something
                // played from search. The cubit ignores ids it already holds.
                listener: (context, history) =>
                    context.read<HomeCubit>().resolveMissing(history.recentIds),
                builder: (context, history) {
                  final sections = state.sectionsFor(history.recentIds);

                  return RefreshIndicator(
                    color: SpotifyColors.green,
                    backgroundColor: SpotifyColors.surfaceBright,
                    onRefresh: () => refreshOrComplain(
                      context,
                      () => context.read<HomeCubit>().refresh(history.recentIds),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      // Otherwise the pull only works when the list is long
                      // enough to scroll.
                      physics: const AlwaysScrollableScrollPhysics(),
                      // +1 for the greeting, which scrolls with the content.
                      itemCount: sections.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return const _Greeting();
                        final section = sections[index - 1];
                        return CatalogSectionRow(
                          section: section,
                          // Under THIS tab, so the tab bar stays and back
                          // returns here.
                          onItemTap: (itemId) =>
                              context.push(Routes.detailUnder(Routes.home, itemId)),
                        );
                      },
                    ),
                  );
                },
              );
          }
        },
      ),
    );
  }
}

/// "Good evening" over the first row. Reads the clock at build time and never
/// updates itself.
///
/// Home is *not* rebuilt per visit -- the tab shell keeps its Navigator alive all
/// session. This holds only because a play-history change rebuilds it, and
/// because nobody watches the greeting across the afternoon/evening boundary.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Semantics(
        header: true,
        child: Text(
          greetingFor(DateTime.now()),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
