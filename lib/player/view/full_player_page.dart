import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../likes/widgets/like_button.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../../widgets/marquee_text.dart';
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
                  // Title/artist take the remaining width (so the marquee
                  // measures overflow against it, not the shrink-wrapped text),
                  // with the like toggle pinned to the right.
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarqueeText(track.title,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                            MarqueeText(track.artist,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: SpotifyColors.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      LikeButton(id: track.id, size: 30),
                    ],
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

class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.state});

  final PlayerState state;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  // While the user is dragging, the slider follows this local value instead of
  // state.position -- otherwise the position ticker keeps overwriting the
  // slider value mid-drag, fighting the finger and making the final seek land
  // at the wrong spot. We seek exactly once, on release.
  double? _dragValue;

  // Tabular figures so every digit is the same width -- the elapsed-time label
  // updates continuously while dragging, and with Poppins' default
  // proportional figures the number visibly wiggles as the digits change.
  TextStyle? _timeStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
        color: SpotifyColors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.state.duration.inMilliseconds;
    final positionMs = widget.state.position.inMilliseconds.clamp(0, totalMs == 0 ? 0 : totalMs);
    final sliderValue = _dragValue ?? positionMs.toDouble();

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
            value: sliderValue.clamp(0, totalMs == 0 ? 1 : totalMs.toDouble()),
            max: totalMs == 0 ? 1 : totalMs.toDouble(),
            onChanged: totalMs == 0 ? null : (value) => setState(() => _dragValue = value),
            onChangeEnd: totalMs == 0
                ? null
                : (value) {
                    context.read<PlayerBloc>().add(PlayerSeekRequested(Duration(milliseconds: value.round())));
                    setState(() => _dragValue = null);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(_dragValue != null ? Duration(milliseconds: _dragValue!.round()) : widget.state.position),
                  style: _timeStyle(context)),
              Text(formatDuration(widget.state.duration), style: _timeStyle(context)),
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

  // Every control lives in a fixed-size box so nothing reflows when the
  // play/pause glyph swaps to a spinner (they differ in size) or when a button
  // enables/disables -- otherwise the center circle resizes and, with
  // spaceEvenly, shoves prev/next sideways during a scrub/seek.
  static const double _sideButton = 56;
  static const double _playButton = 64;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PlayerBloc>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SizedBox(
          width: _sideButton,
          height: _sideButton,
          child: IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_previous),
            color: state.hasPrevious ? Colors.white : Colors.white38,
            onPressed: state.hasPrevious ? () => bloc.add(const PlayerPreviousRequested()) : null,
          ),
        ),
        SizedBox(
          width: _playButton,
          height: _playButton,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: SpotifyColors.green, shape: BoxShape.circle),
            child: IconButton(
              iconSize: 32,
              // The outer 64x64 SizedBox pins the circle, so swapping the glyph
              // for the spinner (different intrinsic size) can't reflow anything.
              icon: state.isLoading
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                  : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
              onPressed: () => bloc.add(const PlayerPlayPauseToggled()),
            ),
          ),
        ),
        SizedBox(
          width: _sideButton,
          height: _sideButton,
          child: IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_next),
            color: state.hasNext ? Colors.white : Colors.white38,
            onPressed: state.hasNext ? () => bloc.add(const PlayerNextRequested()) : null,
          ),
        ),
      ],
    );
  }
}
