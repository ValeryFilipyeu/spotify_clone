/// The seam over the OS *audio* session -- our claim on the device's speaker.
///
/// Distinct from [MediaSession], which is remote control (lock screen,
/// notification, headset buttons). This is about ownership: taking the audio
/// device, giving it back, and being told when something else takes it.
///
/// Claiming it is not optional book-keeping. Nothing else in the stack does it
/// -- neither just_audio nor audio_service calls setCategory or setActive (both
/// were checked) -- and an unclaimed session means iOS leaves the app on a
/// category that MIXES with other apps: another app's audio plays *over* ours
/// and we are never told to stop. On Android there is no audio focus request at
/// all, so nothing is reported either.
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

/// Something else wants the speaker. [duck] distinguishes the two very
/// different remedies: a transient prompt (turn-by-turn directions) should play
/// *over* quieter music, while a phone call means stop entirely.
class AudioInterruptionBegan extends AudioInterruption {
  const AudioInterruptionBegan({required this.duck});

  final bool duck;
}

/// We have the audio device back. [shouldResume] is the OS's own opinion, not
/// ours: after a phone call it is true, but after an indefinite interruption the
/// platform reports unknown and we must stay paused rather than surprise anyone.
class AudioInterruptionEnded extends AudioInterruption {
  const AudioInterruptionEnded({required this.shouldResume});

  final bool shouldResume;
}

/// Headphones unplugged, or Bluetooth disconnected. Every platform's convention
/// is the same here: pause, and NEVER auto-resume -- otherwise the phone's
/// speaker suddenly blares music into a quiet room.
class AudioOutputDisconnected extends AudioInterruption {
  const AudioOutputDisconnected();
}

/// Used where there is no OS audio session: unit tests, and platforms that do
/// not arbitrate one. Never emits, so the player behaves exactly as it did
/// before interruption handling existed.
class NoopPlaybackAudioSession implements PlaybackAudioSession {
  const NoopPlaybackAudioSession();

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Stream<AudioInterruption> get interruptions => const Stream.empty();
}
