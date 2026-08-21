import 'package:spotify_clone/storage/key_value_store.dart';

/// An in-memory [KeyValueStore] that also records what was asked of it.
///
/// The recording is the point. A cache is judged as much by what it *did not*
/// do -- a read that never reached storage, a write that happened once rather
/// than per entry -- and a plain map cannot answer either question.
class FakeKeyValueStore implements KeyValueStore {
  /// Directly readable and writable, so a test can plant a value that this
  /// class's own API could not produce: a payload from an older schema version,
  /// or a half-written one.
  final Map<String, String> values = {};

  final List<String> reads = [];
  final List<String> writes = [];
  final List<String> deletes = [];

  /// Makes every write fail, standing in for a full disk or a store that has
  /// gone away.
  bool failWrites = false;

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    if (failWrites) throw StateError('storage is full');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes.add(key);
    values.remove(key);
  }

  /// The keys currently held, ignoring the order they went in.
  Set<String> get keys => values.keys.toSet();

  void clearLog() {
    reads.clear();
    writes.clear();
    deletes.clear();
  }
}
