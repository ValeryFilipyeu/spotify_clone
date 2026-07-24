import 'package:shared_preferences/shared_preferences.dart';

/// A tiny key-value abstraction for *non-sensitive*, locally-persisted state
/// (the counterpart to auth's [SessionStorage], which is Keychain-backed and
/// reserved for secrets). Repositories depend on this interface, not on
/// shared_preferences directly, so tests use an in-memory fake and the backing
/// store can be swapped without touching callers.
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The production [KeyValueStore], backed by shared_preferences -- the standard
/// place for small, non-secret preferences (likes, settings). Works across
/// web, iOS, Android and macOS. The [SharedPreferences] instance is obtained
/// once in main() and injected, so nothing here awaits a platform channel per
/// call.
class SharedPreferencesStore implements KeyValueStore {
  const SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}
