import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../history/cubit/play_history_cubit.dart';
import '../../likes/widgets/like_button.dart';
import '../../player/bloc/player_bloc.dart';
import '../../player/bloc/player_event.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../models/search_results.dart';
import 'cover_art.dart';

/// A single song row for a [TrackHit], shared by Search results and the Library
/// "Songs" section. Tapping it plays the track (as its own one-song queue),
/// the subtitle attributes it to its album/playlist, and the trailing heart
/// toggles the like. Highlights green while it is the current track.
class TrackHitTile extends StatelessWidget {
  const TrackHitTile({super.key, required this.hit});

  final TrackHit hit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentId = context.select<PlayerBloc, String?>((bloc) => bloc.state.currentTrack?.id);
    final isCurrent = hit.track.id == currentId;

    return Semantics(
      // Same reason as TrackTile: "playing right now" is a green title and
      // nothing else, so it has to be said as well as shown.
      selected: isCurrent,
      child: _tile(context, textTheme, isCurrent),
    );
  }

  Widget _tile(BuildContext context, TextTheme textTheme, bool isCurrent) {
    return ListTile(
      // A song has no cover of its own, so it borrows its album's -- which is
      // already here for the subtitle.
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
          LikeButton(id: hit.track.id, itemName: hit.track.title),
        ],
      ),
      onTap: () {
        context.read<PlayerBloc>().add(PlayerTrackStarted(queue: [hit.track], startIndex: 0));
        // Credited to the album it came from, not to the one-song queue: what
        // Home offers to replay is a playlist, not a single track.
        context.read<PlayHistoryCubit>().record(hit.album.id);
      },
    );
  }
}
