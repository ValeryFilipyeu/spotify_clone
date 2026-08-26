import 'dart:convert';

import '../../storage/key_value_store.dart';
import '../models/liked_id.dart';
import 'likes_repository.dart';

/// A [LikesRepository] that persists each user's library to a [KeyValueStore] as
/// a JSON array of [LikedId.encode] strings, under a key namespaced by user id
/// (`liked_ids:<userId>`). Sets are cached in memory per user after the first
/// read so repeated fetches and toggles don't re-hit storage.
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

  /// Reads the stored array, keeping only the entries that are still meaningful.
  ///
  /// Anything unparseable is dropped rather than repaired: a malformed payload
  /// and an entry left by the untyped version look the same from here, and both
  /// answers to "what kind of thing is this?" would be guesses. See
  /// [LikedId.tryParse]. The survivors are written back whole on the next toggle,
  /// so the discarded entries do not linger.
  Set<LikedId> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final entries = (jsonDecode(raw) as List).whereType<String>();
      return entries.map(LikedId.tryParse).nonNulls.toSet();
    } on FormatException {
      // Not JSON at all. Same treatment: an empty library, not a crash on
      // startup.
      return {};
    }
  }

  /// Applies [change] to a *copy* of [userId]'s current set; if it actually
  /// changed anything, persists the copy and only then commits it to the cache
  /// -- so a failed write leaves the in-memory set untouched (consistent with
  /// storage).
  Future<void> _mutate(String userId, bool Function(Set<LikedId> ids) change) async {
    final next = {...await fetchLikedIds(userId)};
    if (!change(next)) return; // already in the desired state
    await _store.write(_keyFor(userId), jsonEncode([for (final id in next) id.encode()]));
    _cache[userId] = next;
  }
}
