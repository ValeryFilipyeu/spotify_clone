/// Our claim on the device's speaker: taking it, giving it back, and being told
/// when something else takes it. Distinct from [MediaSession], which is remote
/// control.
///
/// Not optional book-keeping. Nothing else in the stack claims it (checked: not
/// just_audio, not audio_service), and unclaimed, iOS leaves the app on a
/// category that mixes with other apps and never tells us to stop.
abstract class PlaybackAudioSession {
  /// Takes the audio device: sets the playback category on iOS, requests audio
  /// focus on Android. Called before playback starts. Idempotent.
  Future<void> activate();

  /// Gives it back, so whatever we interrupted can carry on.
  Future<void> deactivate();

  /// Something else took the device (a call, Siri, a navigation prompt), or the
  /// output went away (headphones unplugged).
  Stream<AudioInterruption> get interruptions;
}

sealed class AudioInterruption {
  const AudioInterruption();
}

/// Something else wants the speaker. [duck] separates the two remedies: a nav
/// prompt plays *over* quieter music, a phone call means stop.
class AudioInterruptionBegan extends AudioInterruption {
  const AudioInterruptionBegan({required this.duck});

  final bool duck;
}

/// The device is back. [shouldResume] is the OS's opinion, not ours: after an
/// indefinite interruption it is unknown, and we stay paused.
class AudioInterruptionEnded extends AudioInterruption {
  const AudioInterruptionEnded({required this.shouldResume});

  final bool shouldResume;
}

/// Headphones unplugged or Bluetooth gone. Pause, and never auto-resume: the
/// speaker would blare music into a quiet room.
class AudioOutputDisconnected extends AudioInterruption {
  const AudioOutputDisconnected();
}

/// For unit tests and platforms that arbitrate no session. Never emits.
class NoopPlaybackAudioSession implements PlaybackAudioSession {
  const NoopPlaybackAudioSession();

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Stream<AudioInterruption> get interruptions => const Stream.empty();
}
