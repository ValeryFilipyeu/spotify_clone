import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/widgets/cover_art.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/marquee_text.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';
import '../bloc/player_state.dart';
import 'equalizer_bars.dart';

/// The persistent bar above every screen while something is loaded. Zero height
/// when the queue is empty, so it is invisible before anything plays.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onTap});

  /// Opens the full player. Passed in from AppView, which owns the router.
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

        // No SafeArea: the NavigationBar below owns the bottom inset.
        return Material(
          color: SpotifyColors.surfaceBright,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Stack(
                          children: [
                            CoverArt(urls: track.coverUrls, borderRadius: 4, iconSize: 22),
                            // Over the artwork, not beside it: the row's width
                            // belongs to the title, which already marquees. The
                            // scrim keeps the green legible on pale photography.
                            Positioned(
                              left: 3,
                              bottom: 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                  // Shown paused too, resting flat: it moves only
                                  // while sound is coming out, so a mid-track
                                  // stall is visible.
                                  child: EqualizerBars(
                                    isActive: state.isPlaying && !state.isLoading,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      // One node, and a live region: nothing about an
                      // auto-advance moves focus, so it would otherwise be silent
                      // to a screen reader. The label changes only with the
                      // track, so ticks do not re-announce.
                      child: Semantics(
                        liveRegion: true,
                        label: 'Now playing: ${track.title} by ${track.artist}',
                        excludeSemantics: true,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarqueeText(
                              track.title,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            MarqueeText(
                              track.artist,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: state.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              state.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                      tooltip: state.isLoading ? 'Loading' : (state.isPlaying ? 'Pause' : 'Play'),
                      onPressed: () =>
                          context.read<PlayerBloc>().add(const PlayerPlayPauseToggled()),
                    ),
                    // PlayerStopped empties the queue, so this bar collapses.
                    IconButton(
                      icon: const Icon(Icons.close, color: SpotifyColors.textSecondary),
                      tooltip: 'Stop',
                      onPressed: () => context.read<PlayerBloc>().add(const PlayerStopped()),
                    ),
                  ],
                ),
                // Decorative: announced, it would read out a bare percentage on
                // every tick.
                ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(SpotifyColors.green),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
