import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/repository/playback_settings_repository.dart';

import '../fake_audio_controller.dart';

/// In-memory settings store that counts writes, so a test can prove the volume
/// slider's continuous updates collapse into a single save.
class _FakeSettingsRepository implements PlaybackSettingsRepository {
  _FakeSettingsRepository([Map<String, double>? seed]) : volumes = {...?seed};

  final Map<String, double> volumes;
  int saveCount = 0;

  @override
  Future<double?> fetchVolume(String userId) async => volumes[userId];

  @override
  Future<void> saveVolume(String userId, double volume) async {
    saveCount++;
    volumes[userId] = volume;
  }
}

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

/// Longer than the bloc's 400ms volume-save debounce.
const _pastDebounce = Duration(milliseconds: 600);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlayerBloc volume persistence', () {
    late FakeAudioController audio;
    late _FakeSettingsRepository settings;
    late StreamController<String?> users;

    setUp(() {
      audio = FakeAudioController();
      settings = _FakeSettingsRepository();
      // Broadcast, like the real authStateChanges: a single-subscription
      // controller's close() would never complete in the one test below that
      // never attaches a listener.
      users = StreamController<String?>.broadcast();
    });

    tearDown(() => users.close());

    PlayerBloc buildBloc() => PlayerBloc(
          audioController: audio,
          settingsRepository: settings,
          userIdChanges: users.stream,
        );

    test('applies the signed-in account\'s saved volume to state and the engine', () async {
      settings.volumes[_alice] = 0.35;
      final bloc = buildBloc();
      addTearDown(bloc.close);

      users.add(_alice);
      await _settle();

      expect(bloc.state.volume, 0.35);
      expect(audio.volumes, [0.35]); // pushed to the engine, not just state
    });

    test('falls back to full volume for an account that never set one', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      users.add(_bob);
      await _settle();

      expect(bloc.state.volume, 1.0);
    });

    test('persists a changed volume once the debounce elapses', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      users.add(_alice);
      await _settle();

      bloc.add(const PlayerVolumeChanged(0.6));
      await _settle();
      // Applied immediately to the engine, but not yet written.
      expect(bloc.state.volume, 0.6);
      expect(settings.saveCount, 0);

      await Future<void>.delayed(_pastDebounce);
      expect(settings.saveCount, 1);
      expect(settings.volumes[_alice], 0.6);
    });

    test('a whole slider drag results in a single write', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      users.add(_alice);
      await _settle();

      // What dragging the slider actually produces: many events in quick
      // succession.
      for (final v in [0.9, 0.8, 0.7, 0.6, 0.5]) {
        bloc.add(PlayerVolumeChanged(v));
        await _settle();
      }
      await Future<void>.delayed(_pastDebounce);

      expect(settings.saveCount, 1); // not 5
      expect(settings.volumes[_alice], 0.5); // the value it landed on
    });

    test('switching accounts loads the new volume and keeps the old one saved', () async {
      settings.volumes[_bob] = 0.15;
      final bloc = buildBloc();
      addTearDown(bloc.close);

      users.add(_alice);
      await _settle();
      bloc.add(const PlayerVolumeChanged(0.75));
      await _settle();

      // Switch before the debounce fires: alice's pending level must still land.
      users.add(_bob);
      await _settle();

      expect(settings.volumes[_alice], 0.75);
      expect(bloc.state.volume, 0.15); // bob's own level
      expect(audio.volumes.last, 0.15);
    });

    test('signing out resets to full volume so it does not leak to the next account', () async {
      settings.volumes[_alice] = 0.1;
      final bloc = buildBloc();
      addTearDown(bloc.close);

      users.add(_alice);
      await _settle();
      expect(bloc.state.volume, 0.1);

      users.add(null);
      await _settle();

      expect(bloc.state.volume, 1.0);
      expect(audio.volumes.last, 1.0);
    });

    test('closing flushes a volume change still inside the debounce window', () async {
      final bloc = buildBloc();
      users.add(_alice);
      await _settle();

      bloc.add(const PlayerVolumeChanged(0.25));
      await _settle();
      expect(settings.saveCount, 0); // debounce still pending

      await bloc.close(); // e.g. app shutting down

      expect(settings.saveCount, 1);
      expect(settings.volumes[_alice], 0.25);
    });

    test('volume changes before sign-in are applied but not persisted', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(const PlayerVolumeChanged(0.5));
      await Future<void>.delayed(_pastDebounce);

      expect(bloc.state.volume, 0.5);
      expect(settings.saveCount, 0); // no account to attribute it to
    });

    test('works without a settings repository (persistence is optional)', () async {
      final bloc = PlayerBloc(audioController: audio);
      addTearDown(bloc.close);

      bloc.add(const PlayerVolumeChanged(0.45));
      await Future<void>.delayed(_pastDebounce);

      expect(bloc.state.volume, 0.45);
      expect(audio.volumes, [0.45]);
    });
  });
}
