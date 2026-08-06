import 'package:flutter/material.dart';

import '../../catalog/models/track.dart';
import '../../likes/widgets/like_button.dart';
import '../../player/widgets/track_queue_menu.dart';
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
    return Semantics(
      // ListTile's own `selected` changes colours but emits no semantics, so
      // without this the green "this is the track playing right now" highlight is
      // information carried by colour alone -- invisible non-visually.
      selected: isCurrent,
      child: _tile(context, textTheme),
    );
  }

  Widget _tile(BuildContext context, TextTheme textTheme) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 24,
        child: Semantics(
          label: 'Track $position',
          excludeSemantics: true,
          child: Text(
            '$position',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: SpotifyColors.textSecondary),
          ),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "3:07" spoken is a clock time, not a length -- see spokenDuration.
          Semantics(
            label: spokenDuration(track.duration),
            excludeSemantics: true,
            child: Text(
              formatDuration(track.duration),
              style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
            ),
          ),
          LikeButton(id: track.id, itemName: track.title),
          TrackQueueMenu(track: track),
        ],
      ),
    );
  }
}
