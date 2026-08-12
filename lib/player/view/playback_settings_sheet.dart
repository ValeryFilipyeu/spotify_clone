import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/spotify_colors.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';
import '../bloc/player_state.dart';

/// Playback preferences, opened from the full player's app bar. Currently just
/// crossfade; it is the natural home for future per-account playback settings.
class PlaybackSettingsSheet extends StatelessWidget {
  const PlaybackSettingsSheet({super.key});

  /// PlayerBloc is provided above MaterialApp, so this modal route can read it.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const PlaybackSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSeconds = PlayerState.maxCrossfadeDuration.inSeconds;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: BlocBuilder<PlayerBloc, PlayerState>(
          builder: (context, state) {
            final seconds = state.crossfadeDuration.inSeconds;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Playback',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text('Crossfade', style: Theme.of(context).textTheme.bodyLarge),
                    ),
                    Text(
                      seconds == 0 ? 'Off' : '$seconds s',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: seconds == 0 ? SpotifyColors.textSecondary : SpotifyColors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: seconds.toDouble(),
                  max: maxSeconds.toDouble(),
                  // One stop per second: crossfade is set in whole seconds, and
                  // divisions make 0 ("Off") easy to hit again.
                  divisions: maxSeconds,
                  label: seconds == 0 ? 'Off' : '$seconds s',
                  // `label` above is only the visual bubble over the thumb; this
                  // is what gets spoken, and it has to name the setting since
                  // Slider has no separate semantics label.
                  semanticFormatterCallback: (value) => value == 0
                      ? 'Crossfade off'
                      : 'Crossfade ${value.round()} ${value.round() == 1 ? 'second' : 'seconds'}',
                  activeColor: SpotifyColors.green,
                  inactiveColor: Colors.white24,
                  onChanged: (value) => context.read<PlayerBloc>().add(
                    PlayerCrossfadeDurationChanged(Duration(seconds: value.round())),
                  ),
                ),
                Text(
                  'Lets you hear the end of one track as the next one begins. '
                  'Tracks shorter than twice the crossfade change over normally.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
