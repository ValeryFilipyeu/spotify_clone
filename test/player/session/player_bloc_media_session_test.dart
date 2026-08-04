import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/bloc/player_state.dart';
import 'package:spotify_clone/player/session/media_session.dart';

import '../fake_audio_controller.dart';
import 'fake_media_session.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'Artist A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'Artist B', duration: Duration(minutes: 4), audioUrl: 'url-2'),
];

/// Commands arrive on a stream, are turned into events, and the bloc processes
/// those asynchronously -- two hops.
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakeAudioController audio;
  late FakeMediaSession session;
  late PlayerBloc bloc;

  setUp(() {
    audio = FakeAudioController();
    session = FakeMediaSession();
    bloc = PlayerBloc(audioController: audio, mediaSession: session);
  });

  tearDown(() async {
    await bloc.close();
    await session.dispose();
  });

  /// Starts the queue and gets the engine into a steady playing state.
  Future<void> start({int startIndex = 0}) async {
    bloc.add(PlayerTrackStarted(queue: _queue, startIndex: startIndex));
    await _settle();
    audio.emitPlaying(true);
    await _settle();
    audio.emitBuffering(false);
    await _settle();
  }

  group('what the OS is told', () {
    test('publishes the track that is playing', () async {
      await start();

      final published = session.last;
      expect(published, isNotNull);
      expect(published!.id, 't1');
      expect(published.title, 'One');
      expect(published.artist, 'Artist A');
      expect(published.duration, const Duration(minutes: 3));
      expect(published.isPlaying, isTrue);
    });

    test('offers only the skip buttons that would do something', () async {
      await start();
      expect(session.last!.hasPrevious, isFalse, reason: 'first track of the queue');
      expect(session.last!.hasNext, isTrue);

      bloc.add(const PlayerNextRequested());
      await _settle();

      expect(session.last!.hasPrevious, isTrue);
      expect(session.last!.hasNext, isFalse, reason: 'last track of the queue');
    });

    test('republishes when playback pauses and resumes', () async {
      await start();
      session.published.clear();

      audio.emitPlaying(false);
      await _settle();
      expect(session.last!.isPlaying, isFalse);

      audio.emitPlaying(true);
      await _settle();
      expect(session.last!.isPlaying, isTrue);
    });

    // The OS extrapolates position from the last value it was given, so pushing
    // a snapshot on every 250ms tick would be four platform round trips a second
    // for no benefit.
    test('stays quiet while only the position advances', () async {
      await start();
      session.published.clear();

      for (var i = 0; i < 12; i++) {
        bloc.add(const PlayerPositionTicked());
        await _settle();
      }

      expect(bloc.state.position, greaterThan(Duration.zero), reason: 'ticks did land');
      expect(session.published, isEmpty);
    });

    // ...but a seek is a jump, and the OS scrubber would drift away from ours.
    test('republishes when the position jumps', () async {
      await start();
      session.published.clear();

      bloc.add(const PlayerSeekRequested(Duration(seconds: 90)));
      await _settle();

      expect(session.published, hasLength(1));
      expect(session.last!.position, const Duration(seconds: 90));
    });

    test('tears the session down when the queue is cleared', () async {
      await start();

      bloc.add(const PlayerStopped());
      await _settle();

      expect(session.clearCount, 1);
    });

    test('does not re-clear an already empty session', () async {
      bloc.add(const PlayerVolumeChanged(0.5));
      await _settle();
      bloc.add(const PlayerVolumeChanged(0.4));
      await _settle();

      expect(session.clearCount, 0, reason: 'nothing was ever published');
    });
  });

  group('what the OS can ask for', () {
    test('play resumes', () async {
      await start();
      audio.emitPlaying(false);
      await _settle();
      final before = audio.playCount;

      session.send(const MediaSessionPlayRequested());
      await _settle();

      expect(audio.playCount, before + 1);
    });

    test('pause pauses', () async {
      await start();

      session.send(const MediaSessionPauseRequested());
      await _settle();

      expect(audio.pauseCount, 1);
    });

    // Regression guard for the reason play/pause are separate events: mapping
    // both onto a toggle would PAUSE here, doing the opposite of what was asked.
    test('play while already playing never pauses', () async {
      await start();

      session.send(const MediaSessionPlayRequested());
      await _settle();

      expect(audio.pauseCount, 0);
    });

    test('pause while already paused never resumes', () async {
      await start();
      audio.emitPlaying(false);
      await _settle();
      final before = audio.playCount;

      session.send(const MediaSessionPauseRequested());
      await _settle();

      expect(audio.playCount, before);
    });

    test('next and previous move through the queue', () async {
      await start();

      session.send(const MediaSessionNextRequested());
      await _settle();
      expect(bloc.state.currentIndex, 1);

      session.send(const MediaSessionPreviousRequested());
      await _settle();
      expect(bloc.state.currentIndex, 0);
    });

    test('seek moves the engine', () async {
      await start();

      session.send(const MediaSessionSeekRequested(Duration(seconds: 42)));
      await _settle();

      expect(audio.seeks, contains(const Duration(seconds: 42)));
      expect(bloc.state.position, const Duration(seconds: 42));
    });

    // Swiping the Android notification away.
    test('stop ends the listening session', () async {
      await start();

      session.send(const MediaSessionStopRequested());
      await _settle();

      expect(bloc.state.queue, isEmpty);
      expect(audio.stopCount, greaterThanOrEqualTo(1));
    });

    test('commands on an empty player are harmless', () async {
      session.send(const MediaSessionPlayRequested());
      session.send(const MediaSessionNextRequested());
      session.send(const MediaSessionSeekRequested(Duration(seconds: 5)));
      await _settle();

      expect(audio.playCount, 0);
      expect(bloc.state.queue, isEmpty);
    });
  });

  // Cover art is the one field the OS fetches for itself, so getting it into the
  // snapshot is all we can verify from here.
  group('artwork', () {
    test('is published for a track that has some', () async {
      const withArt = Track(
        id: 't3',
        title: 'Three',
        artist: 'Artist C',
        duration: Duration(minutes: 2),
        audioUrl: 'url-3',
        coverUrl: 'https://example.test/cover.jpg',
      );

      bloc.add(const PlayerTrackStarted(queue: [withArt], startIndex: 0));
      await _settle();

      expect(session.last?.artUrl, 'https://example.test/cover.jpg');
    });

    test('is simply absent for a track without any', () async {
      bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
      await _settle();

      expect(session.last?.artUrl, isNull);
    });

    // Artwork only ever changes with the track, and the id already forces a
    // publish -- so it must not turn every position tick into a channel hop.
    test('does not become a reason to republish', () async {
      const withArt = Track(
        id: 't3',
        title: 'Three',
        artist: 'Artist C',
        duration: Duration(minutes: 2),
        audioUrl: 'url-3',
        coverUrl: 'https://example.test/cover.jpg',
      );

      expect(
        NowPlaying.from(const PlayerState(queue: [withArt]), withArt).signature,
        isNot(contains('example.test')),
      );
    });
  });

  test('a player with no media session behaves exactly as before', () async {
    final plain = PlayerBloc(audioController: audio); // no mediaSession
    addTearDown(plain.close);

    plain.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();

    expect(plain.state.currentTrack?.id, 't1');
    expect(audio.setUrls, contains('url-1'));
  });
}
