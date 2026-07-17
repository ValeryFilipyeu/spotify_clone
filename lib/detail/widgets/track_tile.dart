import 'package:flutter/material.dart';

import '../../catalog/models/track.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';

/// One row in the tracklist: position number, title + artist, and duration.
class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.position, required this.track, this.onTap, this.isCurrent = false});

  final int position;
  final Track track;
  final VoidCallback? onTap;

  /// Highlights the row (in brand green) when it is the currently-playing track.
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 24,
        child: Text(
          '$position',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: SpotifyColors.textSecondary),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent ? TextStyle(color: SpotifyColors.green) : null,
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
      ),
      trailing: Text(
        formatDuration(track.duration),
        style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
      ),
    );
  }
}
