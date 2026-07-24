import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/widgets/catalog_list_tile.dart';
import '../../catalog/widgets/sliver_section_header.dart';
import '../../catalog/widgets/track_hit_tile.dart';
import '../../likes/cubit/likes_cubit.dart';
import '../../likes/cubit/likes_state.dart';
import '../../router/app_routes.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/error_retry.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

/// "Your Library" = everything the user has liked. This cubit-loaded catalog is
/// intersected with the app-wide [LikesCubit] set, so unliking an item here
/// (or anywhere) makes it drop out of the list immediately.
class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Library')),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, libState) {
          switch (libState.status) {
            case LibraryStatus.initial:
            case LibraryStatus.loading:
              return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
            case LibraryStatus.failure:
              return ErrorRetry(
                message: libState.errorMessage ?? 'Something went wrong.',
                onRetry: () => context.read<LibraryCubit>().loadLibrary(),
              );
            case LibraryStatus.success:
              return BlocBuilder<LikesCubit, LikesState>(
                builder: (context, likes) {
                  if (likes.status == LikesStatus.loading) {
                    return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
                  }
                  final likedItems = libState.allItems.where((i) => likes.isLiked(i.id)).toList();
                  final likedTracks = libState.allTracks.where((h) => likes.isLiked(h.track.id)).toList();

                  if (likedItems.isEmpty && likedTracks.isEmpty) {
                    return const _EmptyLibrary();
                  }

                  return CustomScrollView(
                    slivers: [
                      if (likedItems.isNotEmpty) ...[
                        const SliverSectionHeader('Playlists & albums'),
                        SliverList.builder(
                          itemCount: likedItems.length,
                          itemBuilder: (context, index) {
                            final item = likedItems[index];
                            return CatalogListTile(
                              item: item,
                              // Push under THIS tab so detail stacks inside Library.
                              onTap: () => context.push(Routes.detailUnder(Routes.library, item.id)),
                            );
                          },
                        ),
                      ],
                      if (likedTracks.isNotEmpty) ...[
                        const SliverSectionHeader('Songs'),
                        SliverList.builder(
                          itemCount: likedTracks.length,
                          itemBuilder: (context, index) => TrackHitTile(hit: likedTracks[index]),
                        ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  );
                },
              );
          }
        },
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border, size: 48, color: SpotifyColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Songs, playlists and albums you like will appear here',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: SpotifyColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
