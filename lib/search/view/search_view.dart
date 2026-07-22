import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/widgets/catalog_list_tile.dart';
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
                hintText: 'Playlists and albums',
                prefixIcon: Icon(Icons.search, color: SpotifyColors.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                switch (state.status) {
                  case SearchStatus.initial:
                  case SearchStatus.loading:
                    return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
                  case SearchStatus.failure:
                    return ErrorRetry(
                      message: state.errorMessage ?? 'Something went wrong.',
                      onRetry: () => context.read<SearchCubit>().loadCatalog(),
                    );
                  case SearchStatus.success:
                    if (state.query.trim().isEmpty) {
                      return const _Hint(icon: Icons.search, text: 'Search playlists and albums');
                    }
                    if (state.results.isEmpty) {
                      return _Hint(icon: Icons.sentiment_dissatisfied_outlined, text: 'No results for "${state.query.trim()}"');
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: state.results.length,
                      itemBuilder: (context, index) {
                        final item = state.results[index];
                        return CatalogListTile(
                          item: item,
                          // push under THIS tab so detail stacks inside Search.
                          onTap: () => context.push(Routes.detailUnder(Routes.search, item.id)),
                        );
                      },
                    );
                }
              },
            ),
          ),
        ],
      ),
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
