/// Per-account playback preferences that outlive a listening session.
///
/// These belong to the account, not the device, so signing in restores the
/// settings that account last used. Shuffle and repeat could join them here
/// later without changing any caller.
///
/// Every getter returns null when the account has never set that preference, so
/// the caller keeps its own default rather than being handed a fake one.
abstract class PlaybackSettingsRepository {
  /// The stored volume (0.0..1.0) for [userId].
  Future<double?> fetchVolume(String userId);

  Future<void> saveVolume(String userId, double volume);

  /// How long tracks should overlap when changing. [Duration.zero] means the
  /// account has explicitly turned crossfade off.
  Future<Duration?> fetchCrossfadeDuration(String userId);

  Future<void> saveCrossfadeDuration(String userId, Duration duration);
}
