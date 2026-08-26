import 'package:shared_preferences/shared_preferences.dart';

/// Local storage for *non-sensitive* state -- the counterpart to auth's
/// Keychain-backed [SessionStorage]. An interface so tests can use an in-memory
/// fake and the backing store can be swapped.
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The production [KeyValueStore], backed by shared_preferences. The instance is
/// obtained once in main() and injected, so nothing awaits a channel per call.
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
