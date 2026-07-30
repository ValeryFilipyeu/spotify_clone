import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

import '../fake_audio_controller.dart';

/// The reported case: one liked song, opened from Your Library, repeat off.
const _single = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
];

const _pair = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

/// Enough turns for a fire-and-forget play() to reach the engine and its
/// playingStream event to come back through the bloc.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeAudioController audio;
  late PlayerBloc bloc;

  setUp(() {
    // These tests are about the engine's own bookkeeping, so the fake has to
    // keep it the way just_audio does -- see strictPlayingContract.
    audio = FakeAudioController()..strictPlayingContract = true;
    bloc = PlayerBloc(audioController: audio);
  });

  tearDown(() => bloc.close());

  /// Plays [queue] from the top and settles into steady playback, exactly as
  /// tapping a row does.
  Future<void> start(List<Track> queue) async {
    bloc.add(PlayerTrackStarted(queue: queue, startIndex: 0));
    await _settle();
    audio.emitBuffering(false); // engine reports the source ready
    await _settle();
    expect(bloc.state.isPlaying, isTrue, reason: 'precondition: we are playing');
  }

  // A source that has run to its end leaves the engine holding play intent
  // (`playing` stays true), parked at the end of a track it still thinks is
  // current. Every failure below comes from leaving it there.
  group('when the last track in the queue ends', () {
    test('the engine is stopped and rewound, not just the state', () async {
      await start(_single);

      audio.emitCompleted();
      await _settle();

      expect(bloc.state.isPlaying, isFalse);
      expect(bloc.state.position, Duration.zero);
      expect(audio.pauseCount, 1, reason: 'the engine has to be told, or play() stays a no-op');
      expect(audio.seeks, [Duration.zero], reason: 'and left where the state says it is');
    });

    // Symptom 1: with the intent left set, just_audio's play() returns on its
    // first line and the button does nothing at all.
    test('pressing play starts the track over', () async {
      await start(_single);
      audio.emitCompleted();
      await _settle();

      bloc.add(const PlayerPlayPauseToggled());
      await _settle();

      expect(bloc.state.isPlaying, isTrue);
    });

    test('so does a play from the lock screen', () async {
      await start(_single);
      audio.emitCompleted();
      await _settle();

      bloc.add(const PlayerResumeRequested());
      await _settle();

      expect(bloc.state.isPlaying, isTrue);
    });

    // Symptom 2: loading a source while the intent is still set makes it sound
    // *without* any playingStream event -- so the transport sat at 0:00, paused,
    // over audible music.
    test('re-tapping the row plays it with a transport that agrees', () async {
      await start(_single);
      audio.emitCompleted();
      await _settle();

      bloc.add(const PlayerTrackStarted(queue: _single, startIndex: 0));
      await _settle();
      audio.emitBuffering(false);
      await _settle();

      expect(bloc.state.isPlaying, isTrue, reason: 'audio is sounding, so the UI must say so');

      // The position ticker only runs while the state says we are playing, so
      // this is the "no progress on the ui side" half of the report.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(bloc.state.position, greaterThan(Duration.zero));
    });

    test('the whole cycle repeats, not just once', () async {
      await start(_single);

      for (var round = 0; round < 3; round++) {
        audio.emitCompleted();
        await _settle();
        expect(bloc.state.isPlaying, isFalse, reason: 'round $round');

        bloc.add(const PlayerPlayPauseToggled());
        await _settle();
        expect(bloc.state.isPlaying, isTrue, reason: 'round $round');
      }
    });
  });

  // The halt is only for a queue that has actually run out: every other
  // completion hands over to another track, and pausing there would fight it.
  group('when something follows', () {
    test('a mid-queue completion advances without stopping the engine', () async {
      await start(_pair);

      audio.emitCompleted();
      await _settle();

      expect(bloc.state.currentIndex, 1);
      expect(audio.pauseCount, 0);
      expect(bloc.state.isPlaying, isTrue);
    });

    test('repeat-one replays without stopping the engine', () async {
      await start(_single);
      bloc.add(const PlayerRepeatModeCycled()); // off -> all
      bloc.add(const PlayerRepeatModeCycled()); // all -> one
      await _settle();

      audio.emitCompleted();
      await _settle();

      expect(audio.pauseCount, 0);
      expect(audio.setUrls, ['url-1', 'url-1']);
      expect(bloc.state.isPlaying, isTrue);
    });

    test('repeat-all wraps without stopping the engine', () async {
      await start(_pair);
      bloc.add(const PlayerRepeatModeCycled()); // off -> all
      await _settle();
      bloc.add(const PlayerQueueIndexSelected(1)); // to the last track
      await _settle();

      audio.emitCompleted();
      await _settle();

      expect(bloc.state.currentIndex, 0);
      expect(audio.pauseCount, 0);
      expect(bloc.state.isPlaying, isTrue);
    });
  });

  // A failed load is the other way playback ends with nobody pressing pause.
  test('a load that fails leaves the engine stopped too', () async {
    await start(_pair);
    audio.failNextLoad = true;

    bloc.add(const PlayerNextRequested());
    await _settle();

    expect(bloc.state.isPlaying, isFalse);
    expect(bloc.state.isLoading, isFalse);
    expect(audio.pauseCount, 1, reason: 'nothing is sounding, so the intent must not survive');
  });
}
