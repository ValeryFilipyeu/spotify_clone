import 'dart:async';

import 'package:spotify_clone/player/session/playback_audio_session.dart';

/// A test double for the OS audio session, so tests can stage a phone call, a
/// navigation prompt, or headphones being yanked out -- and check that the app
/// actually claims the audio device before it makes a sound.
class FakePlaybackAudioSession implements PlaybackAudioSession {
  final _controller = StreamController<AudioInterruption>.broadcast();

  int activateCount = 0;
  int deactivateCount = 0;

  @override
  Stream<AudioInterruption> get interruptions => _controller.stream;

  @override
  Future<void> activate() async => activateCount++;

  @override
  Future<void> deactivate() async => deactivateCount++;

  void begin({bool duck = false}) => _controller.add(AudioInterruptionBegan(duck: duck));

  void end({required bool shouldResume}) =>
      _controller.add(AudioInterruptionEnded(shouldResume: shouldResume));

  void unplugHeadphones() => _controller.add(const AudioOutputDisconnected());

  Future<void> dispose() => _controller.close();
}
