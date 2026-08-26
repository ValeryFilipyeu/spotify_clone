import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../history/cubit/play_history_cubit.dart';
import '../../likes/models/liked_id.dart';
import '../../likes/widgets/like_button.dart';
import '../../player/bloc/player_bloc.dart';
import '../../player/bloc/player_event.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../models/search_results.dart';
import 'cover_art.dart';

/// A song row for a [TrackHit], shared by Search and Library. Tapping plays it
/// as a one-song queue; it highlights green while current.
class TrackHitTile extends StatelessWidget {
  const TrackHitTile({super.key, required this.hit});

  final TrackHit hit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentId = context.select<PlayerBloc, String?>((bloc) => bloc.state.currentTrack?.id);
    final isCurrent = hit.track.id == currentId;

    return Semantics(
      // "Playing right now" is a colour and nothing else, so it has to be said.
      selected: isCurrent,
      child: _tile(context, textTheme, isCurrent),
    );
  }

  Widget _tile(BuildContext context, TextTheme textTheme, bool isCurrent) {
    return ListTile(
      // A song borrows its album's cover, already here for the subtitle.
      leading: SizedBox(
        width: 40,
        height: 40,
        child: CoverArt(
          urls: hit.album.coverUrls,
          color: hit.album.coverColor,
          borderRadius: 4,
          iconSize: 20,
        ),
      ),
      title: Text(
        hit.track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent ? const TextStyle(color: SpotifyColors.green) : null,
      ),
      subtitle: Text(
        'Song • ${hit.track.artist} • ${hit.album.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: spokenDuration(hit.track.duration),
            excludeSemantics: true,
            child: Text(
              formatDuration(hit.track.duration),
              style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
            ),
          ),
          LikeButton(likedId: LikedId.track(hit.track.id), itemName: hit.track.title),
        ],
      ),
      onTap: () {
        context.read<PlayerBloc>().add(PlayerTrackStarted(queue: [hit.track], startIndex: 0));
        // Credited to its album: what Home offers to replay is a playlist.
        context.read<PlayHistoryCubit>().record(hit.album.id);
      },
    );
  }
}
