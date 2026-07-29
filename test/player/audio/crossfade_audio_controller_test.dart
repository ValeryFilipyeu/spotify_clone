import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/audio/crossfade_audio_controller.dart';

import '../fake_audio_controller.dart';

/// Short ramp so tests finish quickly: 50ms fade in 10ms steps = 5 steps.
const _rampStep = Duration(milliseconds: 10);
const _fade = Duration(milliseconds: 50);

/// Comfortably longer than a whole ramp.
Future<void> _afterRamp() => Future<void>.delayed(const Duration(milliseconds: 150));

/// Builds the decorator over two fakes and hands back all three.
({CrossfadeAudioController controller, FakeAudioController a, FakeAudioController b}) _build() {
  final players = <FakeAudioController>[];
  final controller = CrossfadeAudioController(
    createPlayer: () {
      final player = FakeAudioController();
      players.add(player);
      return player;
    },
    rampStep: _rampStep,
  );
  return (controller: controller, a: players[0], b: players[1]);
}

void main() {
  group('CrossfadeAudioController', () {
    test('reports crossfade support and starts on the first player', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);

      expect(controller.supportsCrossfade, isTrue);

      await controller.setUrl('url-1');
      expect(a.setUrls, ['url-1']);
      expect(b.setUrls, isEmpty); // the spare is untouched
    });

    test('loads the next track silently on the spare player and plays it', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: _fade);

      // The incoming track goes to the OTHER player, muted, and starts at once.
      expect(b.setUrls, ['url-2']);
      expect(b.playCount, 1);
      expect(b.volumes.first, 0);
      // The outgoing player was never asked to load it.
      expect(a.setUrls, ['url-1']);
    });

    test('ramps the two players past each other, then retires the outgoing one', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: _fade);
      await _afterRamp();

      // Outgoing faded to silence and was stopped...
      expect(a.stopCount, 1);
      expect(a.volumes, contains(0.0));
      // ...and left at full volume, ready to be reused for the next track.
      expect(a.volumes.last, 1.0);
      // Incoming ended up at the requested level.
      expect(b.volumes.last, 1.0);
      // The fade was gradual, not a single jump.
      expect(b.volumes.length, greaterThan(2));
    });

    test('the outgoing track completing does not reach the listener', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      final completions = <void>[];
      controller.completedStream.listen(completions.add);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: _fade);

      // The old track reaching its natural end mid-fade must be swallowed --
      // forwarding it would make the bloc skip a track.
      a.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(completions, isEmpty);

      // The NEW track's completion is what counts from here on.
      b.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(completions, hasLength(1));
    });

    test('forwards the incoming player\'s streams after the handover', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      final durations = <Duration?>[];
      controller.durationStream.listen(durations.add);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: _fade);

      b.emitDuration(const Duration(seconds: 42));
      a.emitDuration(const Duration(seconds: 99)); // stale player
      await Future<void>.delayed(Duration.zero);

      expect(durations, [const Duration(seconds: 42)]);
    });

    test('a zero fade is just an ordinary track change on the same player', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: Duration.zero);

      expect(a.setUrls, ['url-1', 'url-2']);
      expect(b.setUrls, isEmpty);
    });

    test('alternates players across consecutive crossfades', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: _fade);
      await _afterRamp();
      await controller.crossfadeTo('url-3', fade: _fade);
      await _afterRamp();

      // Third track lands back on the first player, now free again.
      expect(a.setUrls, ['url-1', 'url-3']);
      expect(b.setUrls, ['url-2']);
    });

    test('an explicit track change cancels a fade in flight', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: const Duration(seconds: 5)); // long fade
      // User hits Next while it is still fading.
      await controller.setUrl('url-3');

      // The half-faded outgoing track is silenced and stopped...
      expect(a.stopCount, 1);
      // ...and the new track loads on the player that is now active (b).
      expect(b.setUrls, ['url-2', 'url-3']);
      // Nothing is left half-faded.
      expect(b.volumes.last, 1.0);
    });

    test('pausing mid-fade freezes it and pauses BOTH tracks', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: const Duration(seconds: 5));
      await controller.pause();

      // Both sides are paused; the outgoing track is NOT thrown away.
      expect(b.pauseCount, 1);
      expect(a.pauseCount, 1);
      expect(a.stopCount, 0, reason: 'pausing must not discard the outgoing track');

      // And the fade really is frozen -- no further volume steps happen.
      final aVolumes = a.volumes.length;
      final bVolumes = b.volumes.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(a.volumes.length, aVolumes);
      expect(b.volumes.length, bVolumes);
    });

    test('resuming carries the frozen fade through to the end', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      await controller.crossfadeTo('url-2', fade: _fade);
      await controller.pause();
      final playsBefore = a.playCount;

      unawaited(controller.play()); // (play() resolves at the track's end)
      await _afterRamp();

      // Both tracks were playing again, and the fade completed properly.
      expect(a.playCount, playsBefore + 1);
      expect(b.volumes.last, 1.0);
      expect(a.stopCount, 1, reason: 'the outgoing track is retired once the fade finishes');
    });

    test('a fade whose track loads while paused stays silent until play', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      b.loadDelay = const Duration(milliseconds: 60);
      final pending = controller.crossfadeTo('url-2', fade: _fade);
      await controller.pause(); // paused while the incoming track is still loading
      await pending;

      // The incoming track was loaded but never started.
      expect(b.setUrls, ['url-2']);
      expect(b.playCount, 0);

      unawaited(controller.play());
      await _afterRamp();

      expect(b.playCount, 1);
      expect(b.volumes.last, 1.0);
    });

    test('volume applies to the active player and scales the fade', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.setVolume(0.5);

      expect(a.volumes.last, 0.5);

      await controller.crossfadeTo('url-2', fade: _fade);
      await _afterRamp();

      // The fade never exceeds the requested level.
      expect(b.volumes.every((v) => v <= 0.5), isTrue);
      expect(b.volumes.last, 0.5);
    });

    test('stop halts both players', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      await controller.crossfadeTo('url-2', fade: const Duration(seconds: 5));

      await controller.stop();

      expect(a.stopCount, greaterThanOrEqualTo(1));
      expect(b.stopCount, greaterThanOrEqualTo(1));
    });

    // Regression: loading the incoming track is a network round-trip, so the
    // outgoing track can reach its natural end while it is still in progress --
    // and back then it was still the "active" player, so that completion was
    // forwarded and the listener skipped a track.
    test('the outgoing track completing DURING the load is still swallowed', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      final completions = <void>[];
      controller.completedStream.listen(completions.add);
      await controller.setUrl('url-1');

      // Incoming track takes a while to load.
      b.loadDelay = const Duration(milliseconds: 100);
      final pending = controller.crossfadeTo('url-2', fade: _fade);

      // The old track ends before the new one has finished loading.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      a.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completions, isEmpty, reason: 'the replaced track ending is not a queue advance');

      await pending;
      await _afterRamp();
      expect(completions, isEmpty);

      // The incoming track's own completion still works afterwards.
      b.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(completions, hasLength(1));
    });

    test('a track change during the load is not overridden when the load lands', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');

      b.loadDelay = const Duration(milliseconds: 100);
      final pending = controller.crossfadeTo('url-2', fade: _fade);

      // User hits Next while the crossfade's track is still loading.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.setUrl('url-3');
      await pending;
      await _afterRamp();

      // The superseded fade must retire what it loaded instead of handing over,
      // so url-3 is what is left playing.
      expect(a.setUrls, ['url-1', 'url-3']);
      expect(b.stopCount, greaterThanOrEqualTo(1));
      expect(a.volumes.isEmpty || a.volumes.last == 1.0, isTrue);
    });

    // Regression: just_audio's play() future resolves only when the track ENDS.
    // Awaiting it inside crossfadeTo parked the whole method for the length of
    // the incoming track, so the handover and the ramp never ran -- the new
    // track played at volume 0 forever and nothing was audible again.
    test('does not wait on play(), which only resolves when the track ends', () async {
      final (controller: controller, a: a, b: b) = _build();
      addTearDown(controller.dispose);
      await controller.setUrl('url-1');
      b.playCompletesOnlyWhenTrackEnds = true;

      // Must return promptly rather than parking until the track finishes.
      await controller.crossfadeTo('url-2', fade: _fade).timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('crossfadeTo awaited play() and never returned'),
          );
      await _afterRamp();

      // The ramp ran, so the incoming track actually became audible.
      expect(b.playCount, 1);
      expect(b.volumes.last, 1.0);
      expect(a.stopCount, 1);
    });

    test('dispose disposes both players', () async {
      final (controller: controller, a: a, b: b) = _build();
      await controller.dispose();

      expect(a.disposed, isTrue);
      expect(b.disposed, isTrue);
    });
  });
}
