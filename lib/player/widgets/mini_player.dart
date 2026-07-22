import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/spotify_colors.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';
import '../bloc/player_state.dart';

/// The persistent bar shown above every screen while something is loaded.
/// Renders nothing (zero height) when the queue is empty, so it is invisible
/// on Landing/Log In and before any track is played.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onTap});

  /// Opens the full "Now Playing" screen. Passed in from AppView (which owns
  /// the router) rather than looked up from context.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerState>(
      builder: (context, state) {
        final track = state.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final progress = state.duration.inMilliseconds == 0
            ? 0.0
            : (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(0.0, 1.0);

        // No SafeArea here: the mini-player sits directly above the tab bar
        // (see ScaffoldWithNavBar), and the NavigationBar below it owns the
        // bottom safe-area inset.
        return Material(
          color: SpotifyColors.surfaceBright,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: _CoverThumb(),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: state.isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                      onPressed: () => context.read<PlayerBloc>().add(const PlayerPlayPauseToggled()),
                    ),
                    // Dismiss the player: stop playback and clear the queue.
                    // PlayerStopped empties the queue, so currentTrack becomes
                    // null and this whole bar collapses to nothing (above).
                    IconButton(
                      icon: const Icon(Icons.close, color: SpotifyColors.textSecondary),
                      tooltip: 'Stop',
                      onPressed: () => context.read<PlayerBloc>().add(const PlayerStopped()),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(SpotifyColors.green),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SpotifyColors.surface, Colors.black],
        ),
      ),
      child: const Icon(Icons.music_note, color: Colors.white70, size: 22),
    );
  }
}
