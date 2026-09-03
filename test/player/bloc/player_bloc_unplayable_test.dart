import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

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
    // The strict contract is the point: just_audio's `playing` is play INTENT,
    // so a play() on a source that never loaded still flips it true. That is
    // exactly the bug -- a moving scrubber over silence.
    audio = FakeAudioController()..strictPlayingContract = true;
    bloc = PlayerBloc(audioController: audio);
  });

  tearDown(() => bloc.close());

  /// Opens a track whose load fails, as tapping one offline does.
  Future<void> openUnplayable() async {
    audio.failNextLoad = true;
    bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
    await _settle();
  }

  test('the track is still open, so the queue and artwork are unchanged', () async {
    await openUnplayable();

    expect(bloc.state.currentTrack, _pair.first);
    expect(bloc.state.queue, _pair);
    expect(bloc.state.isUnplayable, isTrue);
  });

  group('the transport does nothing', () {
    test('play is refused, so the button never turns into pause', () async {
      await openUnplayable();
      audio.playCount = 0;

      bloc.add(const PlayerPlayPauseToggled());
      await _settle();

      expect(audio.playCount, 0, reason: 'nothing may reach the engine');
      expect(bloc.state.isPlaying, isFalse);
    });

    test('resume from the lock screen is refused too', () async {
      await openUnplayable();
      audio.playCount = 0;

      bloc.add(const PlayerResumeRequested());
      await _settle();

      expect(audio.playCount, 0);
      expect(bloc.state.isPlaying, isFalse);
    });

    test('the scrubber cannot be dragged anywhere', () async {
      await openUnplayable();

      bloc.add(const PlayerSeekRequested(Duration(seconds: 42)));
      await _settle();

      expect(bloc.state.position, Duration.zero);
      expect(audio.seeks, isEmpty);
    });

    test('and the position never advances on its own', () async {
      await openUnplayable();

      // The ticker only runs while isPlaying; press play, then tick anyway.
      bloc.add(const PlayerPlayPauseToggled());
      await _settle();
      bloc.add(const PlayerPositionTicked());
      await _settle();

      expect(bloc.state.position, Duration.zero);
    });
  });

  group('getting out of it', () {
    test('moving to the next track re-enables everything', () async {
      await openUnplayable();

      bloc.add(const PlayerNextRequested());
      await _settle();

      expect(bloc.state.currentTrack, _pair[1]);
      expect(bloc.state.isUnplayable, isFalse);
    });

    test('next still works, or there would be no way out', () async {
      await openUnplayable();

      expect(bloc.state.hasNext, isTrue);
      bloc.add(const PlayerNextRequested());
      await _settle();

      expect(audio.setUrls.last, 'url-2');
    });

    test('a retry that succeeds clears the verdict', () async {
      await openUnplayable();

      // Re-tapping the row is how a person retries; the load works this time.
      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();

      expect(bloc.state.isUnplayable, isFalse);
      expect(bloc.state.unplayableTrack, isNull);
    });

    test('a retry that fails again is reported again', () async {
      await openUnplayable();
      final announcements = <Track?>[];
      final sub = bloc.stream.listen((state) => announcements.add(state.unplayableTrack));

      audio.failNextLoad = true;
      bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
      await _settle();

      // Cleared on the attempt, set again on the failure: a listener keyed on
      // null -> non-null sees a second event rather than nothing.
      expect(announcements, contains(null));
      expect(announcements.last, _pair.first);
      await sub.cancel();
    });
  });
}
