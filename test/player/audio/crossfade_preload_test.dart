import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/audio/crossfade_audio_controller.dart';

import '../fake_audio_controller.dart';

/// Short ramp so tests finish quickly: 50ms fade in 10ms steps = 5 steps.
const _rampStep = Duration(milliseconds: 10);
const _fade = Duration(milliseconds: 50);

/// A load slow enough that "did the fade wait for it?" is observable. Longer
/// than the whole fade, which is the case that used to remove the crossfade
/// entirely.
const _slowLoad = Duration(milliseconds: 120);

Future<void> _afterRamp() => Future<void>.delayed(const Duration(milliseconds: 200));

({CrossfadeAudioController controller, FakeAudioController a, FakeAudioController b}) _build({
  Duration loadDelay = Duration.zero,
}) {
  final players = <FakeAudioController>[];
  final controller = CrossfadeAudioController(
    createPlayer: () {
      final player = FakeAudioController()..loadDelay = loadDelay;
      players.add(player);
      return player;
    },
    rampStep: _rampStep,
  );
  return (controller: controller, a: players[0], b: players[1]);
}

void main() {
  group('CrossfadeAudioController preload', () {
    test('buffers the next track on the spare player without sounding it', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.preload('url-2');

      expect(b.setUrls, ['url-2'], reason: 'loaded on the spare player');
      expect(b.volumes, contains(0.0), reason: 'silent while it waits');
      expect(b.playCount, 0, reason: 'preloading must never start playback');
      expect(a.setUrls, ['url-1'], reason: 'the sounding player is untouched');
    });

    test('is deduped, so driving it from a position ticker costs one load', () async {
      final (controller: controller, b: b, a: _) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      for (var i = 0; i < 10; i++) {
        await controller.preload('url-2');
      }

      expect(b.setUrls, ['url-2']);
    });

    test('a preloaded track is not loaded again by the fade', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.preload('url-2');

      await controller.crossfadeTo('url-2', fade: _fade);

      expect(b.setUrls, ['url-2'], reason: 'loaded once, by the preload');
      expect(b.playCount, 1, reason: 'the fade only has to start it');
    });

    // THE POINT of preloading. Without it, crossfadeTo spends the start of the
    // fade waiting on the network: the outgoing track plays on alone and the
    // overlap is cut short (or lost completely when the load outlasts the fade).
    test('a preloaded fade begins immediately instead of waiting on the load', () async {
      final (controller: controller, a: a, b: b) = _build(loadDelay: _slowLoad);
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.preload('url-2');
      a.volumes.clear();

      final stopwatch = Stopwatch()..start();
      await controller.crossfadeTo('url-2', fade: _fade);
      stopwatch.stop();

      expect(
        stopwatch.elapsed,
        lessThan(_slowLoad),
        reason: 'the handover must not wait for a load that already happened',
      );
      await _afterRamp();
      expect(a.volumes, isNotEmpty, reason: 'the outgoing track actually faded down');
      expect(a.volumes, contains(0.0), reason: 'and reached silence');
      // Retiring the player restores it to the requested volume, ready for reuse.
      expect(a.volumes.last, 1.0);
    });

    test('falls back to loading when the fade wants a different track', () async {
      final (controller: controller, b: b, a: _) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.preload('url-2'); // queue changed after this

      await controller.crossfadeTo('url-3', fade: _fade);

      expect(b.setUrls, ['url-2', 'url-3'], reason: 'the wanted track still loads');
      expect(b.playCount, 1);
    });

    test('replaces a stale preload when the next track changes', () async {
      final (controller: controller, b: b, a: _) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.preload('url-2');
      await controller.preload('url-3');

      expect(b.setUrls, ['url-2', 'url-3']);
    });

    // Regression guard: stop() releases both players, so a preload that survived
    // it would be reported ready while its source was gone -- the fade would
    // "start" a silent player.
    test('stop() discards the preload, so a later fade loads for real', () async {
      final (controller: controller, b: b, a: _) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.preload('url-2');

      await controller.stop();
      await controller.setUrl('url-1');
      await controller.crossfadeTo('url-2', fade: _fade);

      expect(b.setUrls, ['url-2', 'url-2'], reason: 'reloaded after the stop');
    });

    // Same hazard via the other path that releases the standby player.
    test('aborting a fade discards the preload it invalidates', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      // A fade in flight owns the standby player, so this is refused outright.
      await controller.crossfadeTo('url-2', fade: _fade);
      await controller.preload('url-3');
      expect(b.setUrls, ['url-2'], reason: 'preload must not touch a fading pair');

      // Next: aborts the fade and cuts to a new track.
      await controller.setUrl('url-4');
      await controller.preload('url-5');
      await controller.crossfadeTo('url-5', fade: _fade);
      await _afterRamp();

      // url-5 was preloaded onto the (now) spare player and reused, not reloaded.
      expect(a.setUrls.where((u) => u == 'url-5').length, 1);
    });

    test('does not disturb a fade already in flight', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.crossfadeTo('url-2', fade: _fade);

      await controller.preload('url-3');
      await _afterRamp();

      // The outgoing player still finished its fade and was retired cleanly.
      expect(a.volumes.last, greaterThan(0.0), reason: 'volume restored on retirement');
      expect(a.stopCount, greaterThanOrEqualTo(1));
      expect(b.setUrls, ['url-2'], reason: 'the incoming track was left alone');
    });
  });
}
