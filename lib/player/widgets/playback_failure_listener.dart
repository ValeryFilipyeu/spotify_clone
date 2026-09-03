import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/offline/offline_status.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_state.dart';

/// Says so when a track will not play, rather than leaving a play button that
/// does nothing.
///
/// The wording is chosen here and not in the bloc: being offline is something the
/// catalog layer knows, and the player only ever learns that a load threw. The
/// two answers deserve different sentences, and neither belongs in the engine.
///
/// In the shell for the same reason [OfflineBanner] is: one insertion point
/// covers every screen, and the messenger sits above the router, so the message
/// still lands over the full player pushed on top.
class PlaybackFailureListener extends StatelessWidget {
  const PlaybackFailureListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<PlayerBloc, PlayerState>(
      // Only the transition into failure. The field now persists -- it also
      // disables the transport -- so without this every later state would
      // re-announce it. A retry clears it first, so a second failure still
      // reads as a new one.
      listenWhen: (previous, current) =>
          current.unplayableTrack != null && previous.unplayableTrack == null,
      listener: (context, state) {
        final track = state.unplayableTrack;
        if (track == null) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<OfflineStatus>().isOffline
                  // Not "download it" -- nothing here is chosen, and on the web
                  // some tracks can never be saved. See WebAudioCache.
                  ? 'Not available offline.'
                  : 'Could not play ${track.title}.',
            ),
          ),
        );
      },
      child: child,
    );
  }
}
