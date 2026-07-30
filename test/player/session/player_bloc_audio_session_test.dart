import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

import '../fake_audio_controller.dart';
import 'fake_playback_audio_session.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakeAudioController audio;
  late FakePlaybackAudioSession session;
  late PlayerBloc bloc;

  setUp(() {
    audio = FakeAudioController();
    session = FakePlaybackAudioSession();
    bloc = PlayerBloc(audioController: audio, audioSession: session);
  });

  tearDown(() async {
    await bloc.close();
    await session.dispose();
  });

  /// Playing, with the engine settled -- the state every interruption starts from.
  Future<void> startPlaying() async {
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();
    audio.emitPlaying(true);
    await _settle();
    audio.emitBuffering(false);
    await _settle();
  }

  // Regression group for the bug that made interruptions never fire at all:
  // nothing in the stack claims the audio session (verified -- neither
  // just_audio nor audio_service calls setCategory/setActive), so without this
  // the app just mixes underneath other apps and is never interrupted.
  group('claiming the audio device', () {
    test('happens before the first track sounds', () async {
      bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
      await _settle();

      expect(session.activateCount, greaterThanOrEqualTo(1));
      expect(audio.setUrls, contains('url-1'));
    });

    test('happens again on every track change', () async {
      await startPlaying();
      final before = session.activateCount;

      bloc.add(const PlayerNextRequested());
      await _settle();

      expect(session.activateCount, greaterThan(before));
    });

    test('happens on resume, since somebody else may own the device now',
        () async {
      await startPlaying();
      audio.emitPlaying(false);
      await _settle();
      final before = session.activateCount;

      bloc.add(const PlayerResumeRequested());
      await _settle();

      expect(session.activateCount, greaterThan(before));
    });

    test('is handed back when the queue is cleared', () async {
      await startPlaying();

      bloc.add(const PlayerStopped());
      await _settle();

      expect(session.deactivateCount, 1);
    });

    test('is not handed back merely for pausing', () async {
      await startPlaying();

      bloc.add(const PlayerPauseRequested());
      await _settle();

      expect(session.deactivateCount, 0, reason: 'a pause is not the end of the session');
    });
  });

  group('a call or Siri taking the speaker', () {
    test('pauses playback', () async {
      await startPlaying();

      session.begin();
      await _settle();

      expect(audio.pauseCount, 1);
    });

    test('resumes afterwards when the platform says it is welcome', () async {
      await startPlaying();
      session.begin();
      await _settle();
      audio.emitPlaying(false);
      await _settle();
      final playsBefore = audio.playCount;

      session.end(shouldResume: true);
      await _settle();

      expect(audio.playCount, playsBefore + 1);
    });

    test('stays paused when the platform will not vouch for resuming', () async {
      await startPlaying();
      session.begin();
      await _settle();
      audio.emitPlaying(false);
      await _settle();
      final playsBefore = audio.playCount;

      session.end(shouldResume: false);
      await _settle();

      expect(audio.playCount, playsBefore);
    });

    // The important one: a call arriving while the user had already paused must
    // not turn into music starting by itself when the call ends.
    test('never resumes something the user had paused themselves', () async {
      await startPlaying();
      bloc.add(const PlayerPlayPauseToggled()); // user pauses
      await _settle();
      audio.emitPlaying(false);
      await _settle();
      final playsBefore = audio.playCount;

      session.begin();
      await _settle();
      session.end(shouldResume: true);
      await _settle();

      expect(audio.playCount, playsBefore, reason: 'we did not stop it, so we do not start it');
    });

    // Same hazard from the other direction: the user pauses *during* the call.
    test('a user pause during the interruption wins', () async {
      await startPlaying();
      session.begin();
      await _settle();
      audio.emitPlaying(false);
      await _settle();

      bloc.add(const PlayerPauseRequested()); // e.g. from the lock screen
      await _settle();
      final playsBefore = audio.playCount;

      session.end(shouldResume: true);
      await _settle();

      expect(audio.playCount, playsBefore);
    });

    test('is harmless with nothing queued', () async {
      session.begin();
      await _settle();
      session.end(shouldResume: true);
      await _settle();

      expect(audio.pauseCount, 0);
      expect(audio.playCount, 0);
    });
  });

  group('a navigation prompt (ducking)', () {
    test('lowers the volume instead of pausing', () async {
      await startPlaying();
      audio.volumes.clear();

      session.begin(duck: true);
      await _settle();

      expect(audio.pauseCount, 0, reason: 'ducking must not stop the music');
      expect(audio.volumes.single, closeTo(0.3, 0.001));
    });

    test('restores the volume afterwards', () async {
      await startPlaying();
      session.begin(duck: true);
      await _settle();
      audio.volumes.clear();

      session.end(shouldResume: false);
      await _settle();

      expect(audio.volumes.single, 1.0);
    });

    test('ducks relative to the volume the user chose', () async {
      await startPlaying();
      bloc.add(const PlayerVolumeChanged(0.5));
      await _settle();
      audio.volumes.clear();

      session.begin(duck: true);
      await _settle();
      expect(audio.volumes.single, closeTo(0.15, 0.001));

      audio.volumes.clear();
      session.end(shouldResume: false);
      await _settle();
      expect(audio.volumes.single, 0.5, reason: 'back to the user setting, not to full');
    });

    // Ducking is an engine-level detail; the user's persisted preference and the
    // volume slider must not move.
    test('leaves the stored volume untouched', () async {
      await startPlaying();
      bloc.add(const PlayerVolumeChanged(0.8));
      await _settle();

      session.begin(duck: true);
      await _settle();

      expect(bloc.state.volume, 0.8);
    });

    test('repeated duck notices do not stack', () async {
      await startPlaying();
      audio.volumes.clear();

      session.begin(duck: true);
      await _settle();
      session.begin(duck: true);
      await _settle();

      expect(audio.volumes, hasLength(1));
    });
  });

  group('headphones unplugged', () {
    test('pauses', () async {
      await startPlaying();

      session.unplugHeadphones();
      await _settle();

      expect(audio.pauseCount, 1);
    });

    // Otherwise music suddenly plays out loud from the phone's speaker.
    test('never auto-resumes, even if an interruption ends later', () async {
      await startPlaying();
      session.unplugHeadphones();
      await _settle();
      audio.emitPlaying(false);
      await _settle();
      final playsBefore = audio.playCount;

      session.end(shouldResume: true);
      await _settle();

      expect(audio.playCount, playsBefore);
    });
  });

  test('a player with no audio session behaves exactly as before', () async {
    final plain = PlayerBloc(audioController: audio);
    addTearDown(plain.close);

    plain.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();

    expect(plain.state.currentTrack?.id, 't1');
  });
}
