import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

import '../fake_audio_controller.dart';

const _fade = Duration(seconds: 6);

/// 3-minute tracks, so the preload window (fade + 8s lead = 14s before the end)
/// is nowhere near the start.
const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlayerBloc preloads the next track', () {
    /// Plays [queue] from [currentIndex], seeks to [position] and fires one
    /// tick -- the tick is where both the preload and the fade are decided.
    Future<PlayerBloc> tickAt(
      Duration position, {
      required FakeAudioController audio,
      Duration crossfade = _fade,
      int currentIndex = 0,
      List<Track> queue = _queue,
      int repeatTaps = 0,
    }) async {
      final bloc = PlayerBloc(audioController: audio);
      addTearDown(bloc.close);

      bloc.add(PlayerTrackStarted(queue: queue, startIndex: currentIndex));
      await _settle();
      if (crossfade > Duration.zero) {
        bloc.add(PlayerCrossfadeDurationChanged(crossfade));
        await _settle();
      }
      for (var i = 0; i < repeatTaps; i++) {
        bloc.add(const PlayerRepeatModeCycled());
        await _settle();
      }
      audio.emitPlaying(true);
      await _settle();
      audio.emitBuffering(false);
      await _settle();
      bloc.add(PlayerSeekRequested(position));
      await _settle();
      audio.preloads.clear();

      bloc.add(const PlayerPositionTicked());
      await _settle();
      return bloc;
    }

    test('buffers the next track before the fade window opens', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      // 180s - 6s fade - 8s lead = 166s.
      await tickAt(const Duration(seconds: 167), audio: audio);

      expect(audio.preloads, ['url-2']);
    });

    test('does not buffer while the track is still far from its end', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      await tickAt(const Duration(seconds: 100), audio: audio);

      expect(audio.preloads, isEmpty);
    });

    test('buffers only once no matter how many ticks pass', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      final bloc = await tickAt(const Duration(seconds: 167), audio: audio);
      for (var i = 0; i < 5; i++) {
        bloc.add(const PlayerPositionTicked());
        await _settle();
      }

      expect(audio.preloads, ['url-2']);
    });

    test('does nothing when crossfade is off', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      await tickAt(const Duration(seconds: 175), audio: audio, crossfade: Duration.zero);

      expect(audio.preloads, isEmpty);
    });

    test('does nothing when the engine cannot overlap sources', () async {
      final audio = FakeAudioController(); // supportsCrossfade: false
      await tickAt(const Duration(seconds: 175), audio: audio);

      expect(audio.preloads, isEmpty);
    });

    test('does not buffer past the end of the queue', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      await tickAt(const Duration(seconds: 175), audio: audio, currentIndex: 1);

      expect(audio.preloads, isEmpty);
    });

    test('buffers the track it will actually fade into when repeat-all wraps', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      // One tap on repeat = repeat-all; on the last track it wraps to the first.
      await tickAt(const Duration(seconds: 167), audio: audio, currentIndex: 1, repeatTaps: 1);

      expect(audio.preloads, ['url-1']);
    });

    test('skips tracks that will change over on a cut anyway', () async {
      final audio = FakeAudioController(supportsCrossfade: true);
      // 10s is not more than twice the 6s fade, so no fade -- and so no preload.
      const shortQueue = [
        Track(
          id: 's1',
          title: 'S1',
          artist: 'A',
          duration: Duration(seconds: 10),
          audioUrl: 'url-s1',
        ),
        Track(
          id: 's2',
          title: 'S2',
          artist: 'B',
          duration: Duration(seconds: 10),
          audioUrl: 'url-s2',
        ),
      ];
      await tickAt(const Duration(seconds: 9), audio: audio, queue: shortQueue);

      expect(audio.preloads, isEmpty);
    });
  });
}
