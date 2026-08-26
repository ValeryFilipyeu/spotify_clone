import 'dart:convert';

import '../../storage/key_value_store.dart';
import '../models/liked_id.dart';
import 'likes_repository.dart';

/// Persists each user's library to a [KeyValueStore] as a JSON array of
/// [LikedId.encode] strings, cached in memory per user after the first read.
class LocalLikesRepository implements LikesRepository {
  LocalLikesRepository(this._store);

  final KeyValueStore _store;

  /// Per-user in-memory copy, authoritative once loaded.
  final Map<String, Set<LikedId>> _cache = {};

  static String _keyFor(String userId) => 'liked_ids:$userId';

  @override
  Future<Set<LikedId>> fetchLikedIds(String userId) async {
    final cached = _cache[userId];
    if (cached != null) return cached;

    return _cache[userId] = _decode(await _store.read(_keyFor(userId)));
  }

  @override
  Future<void> like(String userId, LikedId likedId) => _mutate(userId, (ids) => ids.add(likedId));

  @override
  Future<void> unlike(String userId, LikedId likedId) =>
      _mutate(userId, (ids) => ids.remove(likedId));

  /// Reads the stored array, dropping anything unparseable rather than repairing
  /// it: from here a malformed entry and one left by the untyped version look the
  /// same, and both repairs would be guesses. See [LikedId.tryParse].
  Set<LikedId> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final entries = (jsonDecode(raw) as List).whereType<String>();
      return entries.map(LikedId.tryParse).nonNulls.toSet();
    } on FormatException {
      // An empty library, not a crash on startup.
      return {};
    }
  }

  /// Applies [change] to a *copy*, persists it, and only then commits it to the
  /// cache -- so a failed write leaves memory consistent with storage.
  Future<void> _mutate(String userId, bool Function(Set<LikedId> ids) change) async {
    final next = {...await fetchLikedIds(userId)};
    if (!change(next)) return; // already in the desired state
    await _store.write(_keyFor(userId), jsonEncode([for (final id in next) id.encode()]));
    _cache[userId] = next;
  }
}
