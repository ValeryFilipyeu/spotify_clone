import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../likes/widgets/like_button.dart';
import '../../player/bloc/player_bloc.dart';
import '../../player/bloc/player_event.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../models/search_results.dart';

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

    return ListTile(
      leading: const SizedBox(
        width: 40,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(color: SpotifyColors.surfaceBright),
          child: Icon(Icons.music_note, color: Colors.white70, size: 20),
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
          Text(
            formatDuration(hit.track.duration),
            style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
          ),
          LikeButton(id: hit.track.id),
        ],
      ),
      onTap: () => context.read<PlayerBloc>().add(
            PlayerTrackStarted(queue: [hit.track], startIndex: 0),
          ),
    );
  }
}
