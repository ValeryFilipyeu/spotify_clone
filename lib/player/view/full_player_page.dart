import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';
import '../bloc/player_state.dart';

/// The full-screen "Now Playing" view, pushed on top of the current screen
/// when the mini-player is tapped. Reads the ambient app-wide PlayerBloc.
class FullPlayerPage extends StatelessWidget {
  const FullPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Now Playing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: BlocBuilder<PlayerBloc, PlayerState>(
        builder: (context, state) {
          final track = state.currentTrack;
          if (track == null) {
            return const Center(child: Text('Nothing playing'));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Large cover placeholder. Expanded + Center + AspectRatio
                  // keeps it a square that fits the available vertical space
                  // (so it never overflows on a wide/desktop viewport).
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [SpotifyColors.surfaceBright, Colors.black],
                            ),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white70, size: 96),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(track.artist,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: SpotifyColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Scrubber(state: state),
                  const SizedBox(height: 8),
                  _Controls(state: state),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final totalMs = state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds.clamp(0, totalMs == 0 ? 0 : totalMs);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: SpotifyColors.green,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: positionMs.toDouble(),
            max: totalMs == 0 ? 1 : totalMs.toDouble(),
            onChanged: totalMs == 0
                ? null
                : (value) => context.read<PlayerBloc>().add(PlayerSeekRequested(Duration(milliseconds: value.round()))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(state.position),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary)),
              Text(formatDuration(state.duration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PlayerBloc>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.skip_previous),
          color: state.hasPrevious ? Colors.white : Colors.white38,
          onPressed: state.hasPrevious ? () => bloc.add(const PlayerPreviousRequested()) : null,
        ),
        Container(
          decoration: const BoxDecoration(color: SpotifyColors.green, shape: BoxShape.circle),
          child: IconButton(
            iconSize: 44,
            icon: state.isLoading
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
            onPressed: () => bloc.add(const PlayerPlayPauseToggled()),
          ),
        ),
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.skip_next),
          color: state.hasNext ? Colors.white : Colors.white38,
          onPressed: state.hasNext ? () => bloc.add(const PlayerNextRequested()) : null,
        ),
      ],
    );
  }
}
