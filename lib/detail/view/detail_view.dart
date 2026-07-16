import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/catalog_detail.dart';
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
              return _ScaffoldedCenter(child: const CircularProgressIndicator(color: SpotifyColors.green));
            case DetailStatus.failure:
              return _ScaffoldedCenter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.errorMessage ?? 'Something went wrong.', textAlign: TextAlign.center),
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
            background: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cover, Color.lerp(cover, Colors.black, 0.7)!],
                ),
              ),
              child: const Center(child: Icon(Icons.music_note, color: Colors.white70, size: 72)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.subtitle, style: textTheme.bodyLarge?.copyWith(color: SpotifyColors.textSecondary)),
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
            (context, index) => TrackTile(position: index + 1, track: detail.tracks[index]),
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
