import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/bloc/player_state.dart';

import '../fake_audio_controller.dart';

const _pair = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeAudioController audio;
  late PlayerBloc bloc;

  setUp(() {
    audio = FakeAudioController()..strictPlayingContract = true;
    bloc = PlayerBloc(audioController: audio);
  });

  tearDown(() => bloc.close());

  group('a load that fails', () {
    test('names the track, so something can say which one', () async {
      audio.failNextLoad = true;

      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();

      expect(bloc.state.unplayableTrack, _pair.first);
    });

    test('keeps saying so, because the transport stays disabled', () async {
      audio.failNextLoad = true;
      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();

      // Anything at all afterwards must not quietly re-enable the track.
      bloc.add(const PlayerVolumeChanged(0.5));
      await _settle();

      expect(bloc.state.unplayableTrack, _pair.first);
      expect(bloc.state.isUnplayable, isTrue);
    });

    test('announces once even so: the listener watches the transition', () async {
      final seen = <Track?>[];
      final sub = bloc.stream.listen((state) => seen.add(state.unplayableTrack));

      audio.failNextLoad = true;
      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();
      bloc.add(const PlayerVolumeChanged(0.5));
      await _settle();

      // Every state after the first carries the same track, so a listener keyed
      // on null -> non-null fires exactly once.
      final transitions = [
        for (var i = 1; i < seen.length; i++)
          if (seen[i - 1] == null && seen[i] != null) seen[i],
      ];
      expect(transitions, hasLength(1));
      await sub.cancel();
    });

    test('still leaves the engine stopped', () async {
      audio.failNextLoad = true;

      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();

      expect(bloc.state.isPlaying, isFalse);
      expect(bloc.state.isLoading, isFalse);
    });
  });

  group('a crossfade that fails', () {
    // A crossfade is started by the ticker nearing the end of a track, never by
    // Next -- that is a plain cut. 175s sits inside a 3-minute track's window.
    test('names the track it was moving to, not the one playing', () async {
      audio = FakeAudioController(supportsCrossfade: true);
      bloc = PlayerBloc(audioController: audio);
      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();
      bloc.add(const PlayerCrossfadeDurationChanged(Duration(seconds: 6)));
      await _settle();
      audio.emitPlaying(true);
      await _settle();
      // The tick handler bails while isLoading, so clear it as a real load does.
      audio.emitBuffering(false);
      await _settle();
      bloc.add(const PlayerSeekRequested(Duration(seconds: 175)));
      await _settle();

      audio.failNextLoad = true;
      bloc.add(const PlayerPositionTicked());
      await _settle();

      expect(audio.crossfades, hasLength(1), reason: 'the crossfade path must be the one tested');
      expect(bloc.state.unplayableTrack, _pair[1]);
    });
  });

  test('a normal load reports no failure', () async {
    bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
    await _settle();

    expect(bloc.state.unplayableTrack, isNull);
  });

  group('PlayerState', () {
    test('copyWith carries the verdict rather than dropping it', () {
      final state = PlayerState(unplayableTrack: _pair.first);

      expect(state.copyWith(position: const Duration(seconds: 3)).unplayableTrack, _pair.first);
    });

    test('copyWith drops it only when asked', () {
      final state = PlayerState(unplayableTrack: _pair.first);

      expect(state.copyWith(clearUnplayable: true).unplayableTrack, isNull);
    });

    test('only the track that failed is unplayable, not the whole queue', () {
      final state = PlayerState(queue: _pair, unplayableTrack: _pair.first);

      expect(state.isUnplayable, isTrue);
      expect(state.copyWith(currentIndex: 1).isUnplayable, isFalse);
    });
  });
}
