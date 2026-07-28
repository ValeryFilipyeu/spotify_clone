import '../../storage/key_value_store.dart';
import 'playback_settings_repository.dart';

/// Persists playback preferences to a [KeyValueStore], keyed per account
/// (`playback_volume:<userId>`) -- the same namespacing LocalLikesRepository
/// uses, and the same non-secure store (volume is a preference, not a secret).
class LocalPlaybackSettingsRepository implements PlaybackSettingsRepository {
  const LocalPlaybackSettingsRepository(this._store);

  final KeyValueStore _store;

  static String _volumeKey(String userId) => 'playback_volume:$userId';

  @override
  Future<double?> fetchVolume(String userId) async {
    final raw = await _store.read(_volumeKey(userId));
    if (raw == null) return null;
    // Tolerate a corrupt/hand-edited value rather than throwing at startup:
    // an unparseable level just means "no preference stored".
    final parsed = double.tryParse(raw);
    return parsed?.clamp(0.0, 1.0);
  }

  @override
  Future<void> saveVolume(String userId, double volume) =>
      _store.write(_volumeKey(userId), volume.clamp(0.0, 1.0).toString());
}
