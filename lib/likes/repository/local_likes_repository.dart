import 'dart:convert';

import '../../storage/key_value_store.dart';
import 'likes_repository.dart';

/// A [LikesRepository] that persists each user's liked-id set to a
/// [KeyValueStore] as a JSON array, under a key namespaced by user id
/// (`liked_ids:<userId>`). Sets are cached in memory per user after the first
/// read so repeated fetches and toggles don't re-hit storage.
class LocalLikesRepository implements LikesRepository {
  LocalLikesRepository(this._store);

  final KeyValueStore _store;

  /// Per-user in-memory copy, authoritative once loaded.
  final Map<String, Set<String>> _cache = {};

  static String _keyFor(String userId) => 'liked_ids:$userId';

  @override
  Future<Set<String>> fetchLikedIds(String userId) async {
    final cached = _cache[userId];
    if (cached != null) return cached;

    final raw = await _store.read(_keyFor(userId));
    final ids = raw == null ? <String>{} : (jsonDecode(raw) as List).cast<String>().toSet();
    return _cache[userId] = ids;
  }

  @override
  Future<void> like(String userId, String id) => _mutate(userId, (ids) => ids.add(id));

  @override
  Future<void> unlike(String userId, String id) => _mutate(userId, (ids) => ids.remove(id));

  /// Applies [change] to a *copy* of [userId]'s current set; if it actually
  /// changed anything, persists the copy and only then commits it to the cache
  /// -- so a failed write leaves the in-memory set untouched (consistent with
  /// storage).
  Future<void> _mutate(String userId, bool Function(Set<String> ids) change) async {
    final next = {...await fetchLikedIds(userId)};
    if (!change(next)) return; // already in the desired state
    await _store.write(_keyFor(userId), jsonEncode(next.toList()));
    _cache[userId] = next;
  }
}
