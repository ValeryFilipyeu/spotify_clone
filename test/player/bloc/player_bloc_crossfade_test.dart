import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/bloc/player_state.dart';
import 'package:spotify_clone/player/repository/playback_settings_repository.dart';

import '../fake_audio_controller.dart';

const _fade = Duration(seconds: 6);

/// 3-minute tracks: comfortably longer than twice the fade.
const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

/// Sits inside the fade window of a 3-minute track (180s - 6s = 174s).
const _insideWindow = Duration(seconds: 175);

class _FakeSettingsRepository implements PlaybackSettingsRepository {
  final Map<String, double> volumes = {};
  final Map<String, Duration> crossfades = {};
  int crossfadeSaveCount = 0;

  @override
  Future<double?> fetchVolume(String userId) async => volumes[userId];

  @override
  Future<void> saveVolume(String userId, double volume) async => volumes[userId] = volume;

  @override
  Future<Duration?> fetchCrossfadeDuration(String userId) async => crossfades[userId];

  @override
  Future<void> saveCrossfadeDuration(String userId, Duration duration) async {
    crossfadeSaveCount++;
    crossfades[userId] = duration;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlayerBloc crossfade trigger', () {
    late FakeAudioController audio;

    setUp(() => audio = FakeAudioController(supportsCrossfade: true));

    /// Seeds a state and fires one position tick, which is where the bloc
    /// decides whether to begin a crossfade.
    Future<PlayerBloc> tickAt(
      Duration position, {
      Duration crossfade = _fade,
      PlayerRepeatMode repeat = PlayerRepeatMode.off,
      int currentIndex = 0,
      List<Track> queue = _queue,
      FakeAudioController? controller,
    }) async {
      final bloc = PlayerBloc(audioController: controller ?? audio);
      addTearDown(bloc.close);

      // Reach the desired state through public events only.
      bloc.add(PlayerTrackStarted(queue: queue, startIndex: currentIndex));
      await _settle();
      if (crossfade > Duration.zero) {
        bloc.add(PlayerCrossfadeDurationChanged(crossfade));
        await _settle();
      }
      // The cycle order (off -> all -> one) matches the enum's declaration
      // order, so index doubles as "how many taps to get here".
      for (var i = 0; i < repeat.index; i++) {
        bloc.add(const PlayerRepeatModeCycled());
        await _settle();
      }
      // Playing + a known position, then one tick.
      (controller ?? audio).emitPlaying(true);
      await _settle();
      (controller ?? audio).emitBuffering(false);
      await _settle();
      bloc.add(PlayerSeekRequested(position));
      await _settle();
      (controller ?? audio).setUrls.clear();
      (controller ?? audio).crossfades.clear();

      bloc.add(const PlayerPositionTicked());
      await _settle();
      return bloc;
    }

    test('starts a crossfade into the next track near the end', () async {
      final bloc = await tickAt(_insideWindow);

      expect(audio.crossfades, hasLength(1));
      expect(audio.crossfades.single.url, 'url-2');
      expect(audio.crossfades.single.fade, _fade);
      // The UI moves to the incoming track right away...
      expect(bloc.state.currentIndex, 1);
      expect(bloc.state.position, Duration.zero);
      // ...and must NOT show a spinner: the whole point is a seamless change.
      expect(bloc.state.isLoading, isFalse);
    });

    test('does nothing until the fade window is reached', () async {
      final bloc = await tickAt(const Duration(seconds: 100));

      expect(audio.crossfades, isEmpty);
      expect(bloc.state.currentIndex, 0);
    });

    test('does nothing when crossfade is switched off', () async {
      final bloc = await tickAt(_insideWindow, crossfade: Duration.zero);

      expect(audio.crossfades, isEmpty);
      expect(bloc.state.currentIndex, 0);
    });

    test('does nothing when the engine cannot overlap sources', () async {
      final plain = FakeAudioController(); // supportsCrossfade: false
      final bloc = await tickAt(_insideWindow, controller: plain);

      expect(plain.crossfades, isEmpty);
      expect(bloc.state.currentIndex, 0); // waits for natural completion instead
    });

    test('skips tracks too short to overlap, instead of skipping in a loop', () async {
      // 10s track with a 6s fade: 10s is not more than 2x6s, so it must not
      // crossfade -- and position 0 must not already count as "near the end".
      const shortQueue = [
        Track(id: 's1', title: 'S1', artist: 'A', duration: Duration(seconds: 10), audioUrl: 'url-s1'),
        Track(id: 's2', title: 'S2', artist: 'B', duration: Duration(seconds: 10), audioUrl: 'url-s2'),
      ];
      final bloc = await tickAt(const Duration(seconds: 9), queue: shortQueue);

      expect(audio.crossfades, isEmpty);
      expect(bloc.state.currentIndex, 0);
    });

    test('does not crossfade past the end of the queue', () async {
      final bloc = await tickAt(_insideWindow, currentIndex: 1); // last track

      expect(audio.crossfades, isEmpty);
      expect(bloc.state.currentIndex, 1);
    });

    test('wraps to the first track when repeat-all is on', () async {
      final bloc = await tickAt(_insideWindow, currentIndex: 1, repeat: PlayerRepeatMode.all);

      expect(audio.crossfades.single.url, 'url-1');
      expect(bloc.state.currentIndex, 0);
    });

    test('crossfades into itself when repeat-one is on', () async {
      final bloc = await tickAt(_insideWindow, repeat: PlayerRepeatMode.one);

      expect(audio.crossfades.single.url, 'url-1');
      expect(bloc.state.currentIndex, 0);
    });

    test('one tick starts one crossfade, not a cascade', () async {
      final bloc = await tickAt(_insideWindow);
      // Position was reset to zero, so further ticks must stay quiet.
      for (var i = 0; i < 5; i++) {
        bloc.add(const PlayerPositionTicked());
        await _settle();
      }

      expect(audio.crossfades, hasLength(1));
      expect(bloc.state.currentIndex, 1);
    });
  });

  group('PlayerBloc crossfade setting', () {
    late FakeAudioController audio;
    late _FakeSettingsRepository settings;
    late StreamController<String?> users;

    setUp(() {
      audio = FakeAudioController(supportsCrossfade: true);
      settings = _FakeSettingsRepository();
      users = StreamController<String?>.broadcast();
    });

    tearDown(() => users.close());

    PlayerBloc buildBloc() => PlayerBloc(
          audioController: audio,
          settingsRepository: settings,
          userIdChanges: users.stream,
        );

    test('is off by default', () {
      final bloc = PlayerBloc(audioController: audio);
      addTearDown(bloc.close);
      expect(bloc.state.crossfadeDuration, Duration.zero);
      expect(bloc.state.isCrossfadeEnabled, isFalse);
    });

    test('is clamped to the supported range', () async {
      final bloc = PlayerBloc(audioController: audio);
      addTearDown(bloc.close);

      bloc.add(const PlayerCrossfadeDurationChanged(Duration(seconds: 99)));
      await _settle();
      expect(bloc.state.crossfadeDuration, PlayerState.maxCrossfadeDuration);

      bloc.add(const PlayerCrossfadeDurationChanged(Duration(seconds: -5)));
      await _settle();
      expect(bloc.state.crossfadeDuration, Duration.zero);
    });

    test('loads per account and persists once per gesture', () async {
      settings.crossfades['alice@spotify.com'] = const Duration(seconds: 8);
      final bloc = buildBloc();
      addTearDown(bloc.close);

      users.add('alice@spotify.com');
      await _settle();
      expect(bloc.state.crossfadeDuration, const Duration(seconds: 8));

      // Dragging the slider produces a burst of events -> one write.
      for (final s in [7, 6, 5, 4]) {
        bloc.add(PlayerCrossfadeDurationChanged(Duration(seconds: s)));
        await _settle();
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(settings.crossfadeSaveCount, 1);
      expect(settings.crossfades['alice@spotify.com'], const Duration(seconds: 4));
    });

    // Regression: dismissing the player used to reset crossfade to Off while
    // keeping volume/shuffle/repeat -- so it silently "switched itself off".
    test('survives clearing the queue, like the other playback preferences', () async {
      final bloc = PlayerBloc(audioController: audio);
      addTearDown(bloc.close);

      bloc.add(const PlayerCrossfadeDurationChanged(Duration(seconds: 9)));
      await _settle();
      bloc.add(const PlayerVolumeChanged(0.4));
      await _settle();

      bloc.add(const PlayerStopped()); // the mini-player's X
      await _settle();

      expect(bloc.state.queue, isEmpty);
      expect(bloc.state.crossfadeDuration, const Duration(seconds: 9));
      expect(bloc.state.volume, 0.4);
    });

    test('resets to off on sign-out so it does not leak between accounts', () async {
      settings.crossfades['alice@spotify.com'] = const Duration(seconds: 10);
      final bloc = buildBloc();
      addTearDown(bloc.close);

      users.add('alice@spotify.com');
      await _settle();
      expect(bloc.state.crossfadeDuration, const Duration(seconds: 10));

      users.add(null);
      await _settle();
      expect(bloc.state.crossfadeDuration, Duration.zero);
    });
  });
}
