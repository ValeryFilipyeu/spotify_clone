import 'dart:convert';

import '../../storage/key_value_store.dart';
import 'play_history_repository.dart';

/// A [PlayHistoryRepository] that persists each account's history to a
/// [KeyValueStore] as a JSON array, under a key namespaced by user id
/// (`play_history:<userId>`). The same shape as [LocalLikesRepository] -- a
/// JSON list rather than a set, because here the order *is* the data.
class LocalPlayHistoryRepository implements PlayHistoryRepository {
  LocalPlayHistoryRepository(this._store);

  final KeyValueStore _store;

  /// Per-user in-memory copy, authoritative once loaded.
  final Map<String, List<String>> _cache = {};

  static String _keyFor(String userId) => 'play_history:$userId';

  @override
  Future<List<String>> fetchRecentIds(String userId) async {
    final cached = _cache[userId];
    if (cached != null) return cached;

    final raw = await _store.read(_keyFor(userId));
    final ids = raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
    // Capped on read as well as on write: a stored list from a build with a
    // larger cap must not leak extra rows into the UI.
    return _cache[userId] = ids.take(PlayHistoryRepository.maxEntries).toList();
  }

  @override
  Future<void> record(String userId, String itemId) async {
    final next = withMostRecent(await fetchRecentIds(userId), itemId);
    // Persist first, then commit to the cache, so a failed write leaves memory
    // agreeing with storage (same ordering as LocalLikesRepository).
    await _store.write(_keyFor(userId), jsonEncode(next));
    _cache[userId] = next;
  }
}
