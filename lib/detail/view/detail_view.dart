import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/catalog_detail.dart';
import '../../catalog/models/track.dart';
import '../../catalog/widgets/cover_art.dart';
import '../../history/cubit/play_history_cubit.dart';
import '../../player/bloc/player_bloc.dart';
import '../../player/bloc/player_event.dart';
import '../../theme/spotify_colors.dart';
import '../cubit/detail_cubit.dart';
import '../cubit/detail_state.dart';
import '../widgets/track_tile.dart';

class DetailView extends StatelessWidget {
  const DetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<DetailCubit, DetailState>(
        builder: (context, state) {
          switch (state.status) {
            case DetailStatus.initial:
            case DetailStatus.loading:
              return _ScaffoldedCenter(
                child: const CircularProgressIndicator(
                  color: SpotifyColors.green,
                  semanticsLabel: 'Loading',
                ),
              );
            case DetailStatus.failure:
              return _ScaffoldedCenter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.errorMessage ?? 'Something went wrong.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            case DetailStatus.success:
              return _DetailContent(detail: state.detail!);
          }
        },
      ),
    );
  }
}

/// A back button over centered content, used for the loading/error states
/// (which have no app bar of their own).
class _ScaffoldedCenter extends StatelessWidget {
  const _ScaffoldedCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          const BackButton(),
          Center(child: child),
        ],
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.detail});

  final CatalogDetail detail;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final cover = Color(item.coverColor);
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: Color.lerp(cover, Colors.black, 0.4),
          flexibleSpace: FlexibleSpaceBar(
            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            centerTitle: true,
            // The cover floats on the item's colour rather than filling the
            // header: a full-bleed photo would fight the pinned title text as
            // the bar collapses over it.
            background: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cover, Color.lerp(cover, Colors.black, 0.7)!],
                ),
              ),
              child: Center(
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child: DecoratedBox(
                    // Matches CoverArt's own default radius, or the shadow shows
                    // square corners behind the rounded cover.
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
                      ],
                    ),
                    child: CoverArt(url: item.coverUrl, color: item.coverColor, iconSize: 64),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.subtitle,
                  style: textTheme.bodyLarge?.copyWith(color: SpotifyColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${detail.tracks.length} songs • ${_formatTotal(detail.totalDuration)}',
                  style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _TrackRow(itemId: item.id, tracks: detail.tracks, index: index),
            childCount: detail.tracks.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// Formats a playlist's total length as "X min" (e.g. 42 min).
  static String _formatTotal(Duration duration) => '${duration.inMinutes} min';
}

/// One tracklist row. Extracted into its own widget so `context.select` is
/// legal here -- provider forbids `select` directly inside a SliverList's
/// itemBuilder (it would rebuild the whole list instead of one row).
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.itemId, required this.tracks, required this.index});

  /// The album/playlist these tracks came from -- what gets recorded as
  /// recently played when one of them is started.
  final String itemId;

  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context) {
    final track = tracks[index];
    // select (not watch) so this row rebuilds only when the current track id
    // changes -- not on every position tick.
    final currentId = context.select<PlayerBloc, String?>((bloc) => bloc.state.currentTrack?.id);
    return TrackTile(
      position: index + 1,
      track: track,
      isCurrent: track.id == currentId,
      onTap: () {
        context.read<PlayerBloc>().add(PlayerTrackStarted(queue: tracks, startIndex: index));
        context.read<PlayHistoryCubit>().record(itemId);
      },
    );
  }
}
