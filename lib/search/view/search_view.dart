import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/models/search_results.dart';
import '../../catalog/widgets/catalog_list_tile.dart';
import '../../catalog/widgets/sliver_section_header.dart';
import '../../catalog/widgets/track_hit_tile.dart';
import '../../router/app_routes.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/error_retry.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';

class SearchView extends StatelessWidget {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              textInputAction: TextInputAction.search,
              onChanged: (value) => context.read<SearchCubit>().queryChanged(value),
              decoration: const InputDecoration(
                hintText: 'Songs, playlists and albums',
                prefixIcon: Icon(Icons.search, color: SpotifyColors.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                switch (state.status) {
                  case SearchStatus.initial:
                    return const _Hint(icon: Icons.search, text: 'Search songs, playlists and albums');
                  case SearchStatus.loading:
                    return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
                  case SearchStatus.failure:
                    return ErrorRetry(
                      message: state.errorMessage ?? 'Something went wrong.',
                      onRetry: () => context.read<SearchCubit>().retry(),
                    );
                  case SearchStatus.success:
                    if (state.results.isEmpty) {
                      return _Hint(icon: Icons.sentiment_dissatisfied_outlined, text: 'No results for "${state.query.trim()}"');
                    }
                    return _Results(results: state.results);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The two result groups ("Playlists & albums", then "Songs") in one scroll
/// view. Either group is omitted when it has no matches.
class _Results extends StatelessWidget {
  const _Results({required this.results});

  final SearchResults results;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (results.items.isNotEmpty) ...[
          const SliverSectionHeader('Playlists & albums'),
          SliverList.builder(
            itemCount: results.items.length,
            itemBuilder: (context, index) {
              final item = results.items[index];
              return CatalogListTile(
                item: item,
                // Push under THIS tab so detail stacks inside Search.
                onTap: () => context.push(Routes.detailUnder(Routes.search, item.id)),
              );
            },
          ),
        ],
        if (results.tracks.isNotEmpty) ...[
          const SliverSectionHeader('Songs'),
          SliverList.builder(
            itemCount: results.tracks.length,
            itemBuilder: (context, index) => TrackHitTile(hit: results.tracks[index]),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: SpotifyColors.textSecondary),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: SpotifyColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
