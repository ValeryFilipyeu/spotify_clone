import 'dart:convert';

import '../../../storage/key_value_store.dart';

/// Timestamped, versioned, capped JSON blobs on the device, for
/// [OfflineCatalogRepository] to fall back on. Knows nothing about the catalog:
/// it owns only what makes disk different from memory -- outliving the build that
/// wrote it, ageing, and running out of room.
///
/// Backed by shared_preferences, which is not a database: the whole file is held
/// in memory and rewritten on every change, so an unrelated like toggle pays for
/// a fat cache. That makes size a correctness concern, and it is measured rather
/// than guessed -- 23 KB for a home screen, 58 KB for a 100-track album, 73 KB for
/// 64 track hits, ~70% of it cover urls. The caps here and on
/// [OfflineCatalogRepository.maxEntities] come from those numbers and total
/// roughly 250 KB; wanting much more than that means sqlite. See
/// `catalog_cache_size_test.dart`.
///
/// Entries are wrapped in `{v, at, data}`. Anything unreadable -- bad JSON, wrong
/// [schemaVersion], missing timestamp -- is a miss *and* is deleted, since none of
/// it can become readable later.
class CatalogCacheStore {
  CatalogCacheStore(
    this._store, {
    this.maxAge = const Duration(days: 7),
    this.maxEvictableEntries = defaultMaxEvictableEntries,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Bumped whenever the shape written by `catalog_json.dart` changes.
  static const int schemaVersion = 1;

  /// Named so the size measurements can assert against the shipped number.
  static const int defaultMaxEvictableEntries = 12;

  /// Namespaces every key, so this store shares one file with likes and settings.
  static const String _prefix = 'catalog_cache:';

  /// Holds the eviction order, as a JSON array of keys.
  static const String _indexKey = '${_prefix}index';

  final KeyValueStore _store;

  /// How long a saved answer may be served. A week suits *this* catalog:
  /// trending playlists, where a week-old copy is a slightly out-of-date library
  /// and still worth showing on a plane.
  final Duration maxAge;

  /// Ceiling on `evictable: true` entries -- the album pages, which are the only
  /// unbounded key. Home and the id-keyed collections are fixed keys and are left
  /// out, or a browsing session could evict the home screen.
  ///
  /// Twelve is a size budget: ~10 KB per typical playlist, so ~120 KB, though
  /// twelve hundred-track ones would be 700 KB. Entries rather than bytes,
  /// because a byte budget means weighing every write.
  final int maxEvictableEntries;

  final DateTime Function() _now;

  /// The payload under [key], or null. Every failure is a miss, never a throw:
  /// the caller is already handling a network problem and could do nothing
  /// different about a storage one.
  Future<Map<String, Object?>?> read(String key) async {
    final raw = await _store.read(_prefix + key);
    if (raw == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _discard(key);
    }

    if (decoded is! Map<String, Object?>) return _discard(key);
    if (decoded['v'] != schemaVersion) return _discard(key);

    final at = decoded['at'];
    if (at is! int) return _discard(key);
    if (_now().difference(DateTime.fromMillisecondsSinceEpoch(at)) > maxAge) {
      return _discard(key);
    }

    final data = decoded['data'];
    if (data is! Map<String, Object?>) return _discard(key);
    return data;
  }

  /// Stores [data] under [key], stamped with now. [evictable] entries are capped
  /// by [maxEvictableEntries]; the default keeps an entry until it ages out.
  Future<void> write(String key, Map<String, Object?> data, {bool evictable = false}) async {
    await _store.write(
      _prefix + key,
      jsonEncode({'v': schemaVersion, 'at': _now().millisecondsSinceEpoch, 'data': data}),
    );
    if (evictable) await _track(key);
  }

  /// Forgets [key] entirely, index entry included.
  Future<void> remove(String key) async {
    await _store.delete(_prefix + key);
    final tracked = await _index();
    if (tracked.remove(key)) await _writeIndex(tracked);
  }

  /// Records [key] as most recently written and drops the oldest past the cap.
  ///
  /// Recency means *written*, not read: bumping on read would mean a disk write
  /// every time the cache is consulted, and for album pages the two events are
  /// nearly the same anyway.
  Future<void> _track(String key) async {
    final tracked = await _index();
    tracked
      // The front is what gets deleted, so position is the point of the index.
      ..remove(key)
      ..add(key);

    while (tracked.length > maxEvictableEntries) {
      await _store.delete(_prefix + tracked.removeAt(0));
    }
    await _writeIndex(tracked);
  }

  Future<List<String>> _index() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final key in decoded)
          if (key is String) key,
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _writeIndex(List<String> keys) => _store.write(_indexKey, jsonEncode(keys));

  /// Deletes an entry that can never be read again and reports the miss.
  Future<Map<String, Object?>?> _discard(String key) async {
    await remove(key);
    return null;
  }
}
