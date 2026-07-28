import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/track.dart';
import '../../theme/spotify_colors.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';

enum _QueueAction { playNext, addToQueue }

/// An overflow menu for queueing a track without interrupting what's playing.
/// Self-contained (it reads the app-wide [PlayerBloc] itself), the same way
/// LikeButton reads LikesCubit -- so any track row can drop it in.
class TrackQueueMenu extends StatelessWidget {
  const TrackQueueMenu({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_QueueAction>(
      icon: const Icon(Icons.more_vert, color: SpotifyColors.textSecondary),
      iconSize: 20,
      tooltip: 'More',
      // Both actions start playback when nothing is queued yet (see PlayerBloc).
      onSelected: (action) {
        final bloc = context.read<PlayerBloc>();
        switch (action) {
          case _QueueAction.playNext:
            bloc.add(PlayerPlayNextEnqueued(track));
          case _QueueAction.addToQueue:
            bloc.add(PlayerQueueAppended(track));
        }
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              action == _QueueAction.playNext ? 'Playing next: ${track.title}' : 'Added to queue: ${track.title}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _QueueAction.playNext,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_play),
            title: Text('Play next'),
          ),
        ),
        PopupMenuItem(
          value: _QueueAction.addToQueue,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.queue_music),
            title: Text('Add to queue'),
          ),
        ),
      ],
    );
  }
}
