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
              return const Center(child: CircularProgressIndicator(color: SpotifyColors.green, semanticsLabel: 'Loading'));
            case HomeStatus.failure:
              return ErrorRetry(
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: () => context
                    .read<HomeCubit>()
                    .loadSections(context.read<PlayHistoryCubit>().state.recentIds),
              );
            case HomeStatus.success:
              // Nested builder, like LibraryView's: the catalog comes from one
              // cubit and what makes this screen *yours* from another, and this
              // is where the two are put together. Playing something anywhere in
              // the app therefore reorders Home with no reload.
              return BlocConsumer<PlayHistoryCubit, PlayHistoryState>(
                // History that arrives (or grows) after Home loaded may name
                // items no row on this screen contains -- something played from
                // search, say. Ask for those specifically; the cubit ignores ids
                // it already holds, so the common case costs nothing.
                listener: (context, history) =>
                    context.read<HomeCubit>().resolveMissing(history.recentIds),
                builder: (context, history) {
                  final sections = state.sectionsFor(history.recentIds);

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    // +1 for the greeting, which scrolls with the content rather
                    // than sitting in the app bar.
                    itemCount: sections.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return const _Greeting();
                      final section = sections[index - 1];
                      return CatalogSectionRow(
                        section: section,
                        // push under THIS tab so the detail screen stacks inside
                        // Home (tab bar stays) and the back button returns here.
                        onItemTap: (itemId) => context.push(Routes.detailUnder(Routes.home, itemId)),
                      );
                    },
                  );
                },
              );
          }
        },
      ),
    );
  }
}

/// "Good evening" over the first row. Reads the clock at build time -- there is
/// nothing to keep in sync, since Home is rebuilt on every visit and no session
/// is long enough for the greeting to go stale mid-scroll.
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
