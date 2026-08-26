/// Playback preferences that outlive a session. Per account, not per device.
///
/// Every getter is null when the account never set that preference, so callers
/// keep their own default rather than being handed a fake one.
abstract class PlaybackSettingsRepository {
  /// The stored volume (0.0..1.0) for [userId].
  Future<double?> fetchVolume(String userId);

  Future<void> saveVolume(String userId, double volume);

  /// How long tracks should overlap when changing. [Duration.zero] means the
  /// account has explicitly turned crossfade off.
  Future<Duration?> fetchCrossfadeDuration(String userId);

  Future<void> saveCrossfadeDuration(String userId, Duration duration);
}
