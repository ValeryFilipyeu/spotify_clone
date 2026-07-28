/// Per-account playback preferences that outlive a listening session.
///
/// Volume is the first (and so far only) one: it belongs to the account, not the
/// device, so signing in restores the level that account last used. Shuffle and
/// repeat could join it here later without changing any caller.
abstract class PlaybackSettingsRepository {
  /// The stored volume (0.0..1.0) for [userId], or null if that account has
  /// never set one -- the caller then keeps its own default.
  Future<double?> fetchVolume(String userId);

  Future<void> saveVolume(String userId, double volume);
}
