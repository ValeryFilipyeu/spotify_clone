import 'package:flutter/material.dart';

import '../../catalog/models/track.dart';
import '../../theme/spotify_colors.dart';

/// One row in the tracklist: position number, title + artist, and duration.
class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.position, required this.track});

  final int position;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      leading: SizedBox(
        width: 24,
        child: Text(
          '$position',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: SpotifyColors.textSecondary),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
      ),
      trailing: Text(
        _formatDuration(track.duration),
        style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
      ),
    );
  }

  /// Formats a track length as "m:ss" (e.g. 3:07).
  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
