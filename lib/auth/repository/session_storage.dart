import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A tiny key-value abstraction over secure storage, so tests never touch a
/// real platform channel and [FakeAuthRepository] does not depend on the
/// concrete flutter_secure_storage package directly.
abstract class SessionStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureSessionStorage implements SessionStorage {
  const SecureSessionStorage(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
