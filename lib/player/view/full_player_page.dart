import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/widgets/cover_art.dart';
import '../../likes/widgets/like_button.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../../widgets/marquee_text.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';
import '../bloc/player_state.dart';
import 'playback_settings_sheet.dart';
import 'queue_sheet.dart';

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
          // Every icon-only control here carries a tooltip: it is the visible
          // hint on desktop/web AND the label a screen reader announces, so one
          // string serves both. Without it this button is unusable non-visually.
          tooltip: 'Close Now Playing',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Now Playing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Playback settings',
            onPressed: () => PlaybackSettingsSheet.show(context),
          ),
        ],
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
                  // Expanded + Center + AspectRatio keeps the cover a square that
                  // fits the available vertical space (so it never overflows on a
                  // wide/desktop viewport). No colour passed: a track has none of
                  // its own, so it gets CoverArt's neutral placeholder.
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CoverArt(url: track.coverUrl, borderRadius: 12, iconSize: 96),
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
                      LikeButton(id: track.id, itemName: track.title, size: 30),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Scrubber(state: state),
                  const SizedBox(height: 8),
                  _Controls(state: state),
                  const SizedBox(height: 8),
                  _BottomBar(state: state),
                  const SizedBox(height: 24),
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
            // The slider's value is milliseconds, which a screen reader would
            // otherwise read out as a bare number ("124000") or a meaningless
            // percentage. This is also where the slider gets its NAME: Slider
            // has no separate semantics label, so the spoken value has to say
            // what it is measuring.
            semanticFormatterCallback: (value) => totalMs == 0
                ? 'Playback position unavailable'
                : 'Position ${spokenDuration(Duration(milliseconds: value.round()))} '
                    'of ${spokenDuration(widget.state.duration)}',
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
  // 48, not 44: Android's minimum tap target is 48dp, and these boxes cap the
  // IconButton inside them, so a 44 box quietly made shuffle and repeat too
  // small to be a legal target (caught by androidTapTargetGuideline).
  static const double _modeButton = 48;
  static const double _sideButton = 56;
  static const double _playButton = 64;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PlayerBloc>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SizedBox(
          width: _modeButton,
          height: _modeButton,
          child: IconButton(
            iconSize: 22,
            icon: const Icon(Icons.shuffle),
            // Green when on, muted when off -- the same on/off language the
            // like button uses.
            color: state.isShuffled ? SpotifyColors.green : SpotifyColors.textSecondary,
            tooltip: state.isShuffled ? 'Disable shuffle' : 'Enable shuffle',
            // Green-vs-grey is the only visual difference; isSelected is what
            // makes the same distinction audible.
            isSelected: state.isShuffled,
            onPressed: () => bloc.add(const PlayerShuffleToggled()),
          ),
        ),
        SizedBox(
          width: _sideButton,
          height: _sideButton,
          child: IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_previous),
            color: state.hasPrevious ? Colors.white : Colors.white38,
            tooltip: 'Previous track',
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
              // Tracks all three states the glyph shows. The spinner contributes
              // no semantics of its own (ProgressIndicator only emits a node when
              // given a semanticsLabel), so while loading this tooltip is the
              // button's ONLY name.
              tooltip: state.isLoading
                  ? 'Loading'
                  : (state.isPlaying ? 'Pause' : 'Play'),
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
            tooltip: 'Next track',
            onPressed: state.hasNext ? () => bloc.add(const PlayerNextRequested()) : null,
          ),
        ),
        SizedBox(
          width: _modeButton,
          height: _modeButton,
          child: IconButton(
            iconSize: 22,
            // repeat-one gets its own glyph; off/all share one and differ by
            // colour, so the button never changes size between modes.
            icon: Icon(state.repeatMode == PlayerRepeatMode.one ? Icons.repeat_one : Icons.repeat),
            color: state.repeatMode == PlayerRepeatMode.off
                ? SpotifyColors.textSecondary
                : SpotifyColors.green,
            // Names the CURRENT mode rather than the next one. The old labels
            // described what pressing would do, which read as a plain lie out
            // loud: repeat-all announced itself as "Repeat one track". A
            // three-way cycle has no honest boolean phrasing, so state it.
            tooltip: switch (state.repeatMode) {
              PlayerRepeatMode.off => 'Repeat off',
              PlayerRepeatMode.all => 'Repeat all tracks',
              PlayerRepeatMode.one => 'Repeat this track',
            },
            isSelected: state.repeatMode != PlayerRepeatMode.off,
            onPressed: () => bloc.add(const PlayerRepeatModeCycled()),
          ),
        ),
      ],
    );
  }
}

/// Volume on the left, queue button on the right -- the row under the transport
/// controls.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PlayerBloc>();

    return Row(
      children: [
        Icon(
          state.volume == 0 ? Icons.volume_off : Icons.volume_down,
          size: 20,
          color: SpotifyColors.textSecondary,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: state.volume,
              // Names itself for the same reason as the scrubber: the two
              // sliders on this screen are otherwise indistinguishable by ear,
              // both announcing a bare percentage.
              semanticFormatterCallback: (value) => 'Volume ${(value * 100).round()} percent',
              // Fires continuously while dragging: setVolume is cheap and
              // applying it live is what makes the slider feel connected.
              onChanged: (value) => bloc.add(PlayerVolumeChanged(value)),
            ),
          ),
        ),
        const Icon(Icons.volume_up, size: 20, color: SpotifyColors.textSecondary),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.queue_music),
          color: SpotifyColors.textSecondary,
          tooltip: 'Queue',
          onPressed: () => QueueSheet.show(context),
        ),
      ],
    );
  }
}
