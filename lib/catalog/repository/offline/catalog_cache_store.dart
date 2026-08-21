import 'dart:convert';

import '../../../storage/key_value_store.dart';

/// Timestamped, versioned, capped JSON blobs on the device, for
/// [OfflineCatalogRepository] to fall back on.
///
/// Deliberately dumb about the catalog: it stores maps under string keys and
/// knows nothing about sections or tracks. What it *does* own is everything that
/// makes a value on disk different from a value in memory -- that it outlives
/// the build that wrote it, that it ages, and that there is a finite amount of
/// room -- so the repository above is left with one question, which is when a
/// saved answer is better than an error.
///
/// ## Why shared_preferences and not a database
///
/// This is the app's existing store for local non-secret state (likes, playback
/// settings), it works on every platform this app targets including the web, and
/// it needs no new dependency. What it is not is a database: the whole file is
/// held in memory and rewritten when anything in it changes -- so a fat cache is
/// paid for by every unrelated write, and toggling a like would rewrite the lot.
///
/// Which makes size a correctness concern here rather than housekeeping, and it
/// is measured rather than assumed -- see `catalog_cache_size_test.dart`, which
/// runs the numbers off the same captured Audius responses the parser is tested
/// against. They came out three to five times larger than the guess that preceded
/// them: a home screen is 23 KB, a 100-track album 58 KB, and 64 remembered track
/// hits 73 KB. About 70% of that is cover urls, since every entity carries a
/// primary and three mirrors at around 100 characters each.
///
/// [maxEvictableEntries] and [OfflineCatalogRepository.maxEntities] are set from
/// those measurements rather than from taste, for a total of roughly 250 KB on
/// this catalog's real data. A catalog wanting to keep meaningfully more than that
/// has outgrown this store and wants sqlite or plain files.
///
/// ## What a stored value carries
///
/// Every entry is wrapped in `{v, at, data}`:
///
///  * **v** is [schemaVersion]. An app update that changes what [encodeItem] and
///    friends write must bump it, and every entry written by the old build then
///    reads as a miss instead of as a wrong answer. This is the one thing a
///    persistent cache needs that an in-memory one does not: the code that wrote
///    the value is not the code reading it.
///  * **at** is when it was written, which is what makes [maxAge] enforceable.
///  * **data** is the payload, always a JSON object.
///
/// Anything unreadable -- not JSON, wrong version, no timestamp, a payload that
/// is not an object -- is treated as a miss *and deleted*, because none of those
/// can become readable later and a key that fails every time is worse than an
/// absent one.
class CatalogCacheStore {
  CatalogCacheStore(
    this._store, {
    this.maxAge = const Duration(days: 7),
    this.maxEvictableEntries = defaultMaxEvictableEntries,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Bumped whenever the shape written by `catalog_json.dart` changes.
  static const int schemaVersion = 1;

  /// Named so the size measurements can assert against the number actually
  /// shipped instead of a copy of it.
  static const int defaultMaxEvictableEntries = 12;

  /// Namespaces every key this class owns, so it shares a store with likes and
  /// settings without either having to know the other exists.
  static const String _prefix = 'catalog_cache:';

  /// Holds the eviction order, as a JSON array of keys.
  static const String _indexKey = '${_prefix}index';

  final KeyValueStore _store;

  /// How long a saved answer may be served after it was written.
  ///
  /// A week, which is a judgement about *this* catalog rather than a general
  /// rule: what is behind these calls is trending playlists and their tracklists,
  /// and a week-old copy of that is a slightly out-of-date music library --
  /// perfectly worth showing to someone on a plane. It is also long enough to
  /// cover a holiday and short enough that nobody is served a snapshot they
  /// cannot remember making.
  ///
  /// The point of having a limit at all is that stale data gets *more* wrong the
  /// older it is while looking exactly as confident, and a saved copy nobody can
  /// date is the one thing worse than an error message.
  final Duration maxAge;

  /// The ceiling on entries written with `evictable: true`.
  ///
  /// Only one kind of key is unbounded -- there is one per album opened -- and
  /// only that kind is counted here. Home and the two id-keyed collections are
  /// fixed keys, so they cannot grow in number, and they are the entries most
  /// worth keeping: capping them alongside the albums would let a browsing
  /// session evict the home screen.
  ///
  /// Twelve, which is a size budget rather than a preference. An album's
  /// tracklist is the one entry whose size a user chooses: the playlists this
  /// catalog actually serves run to a handful of tracks and about 10 KB, so twelve
  /// of them is around 120 KB, while twelve hundred-track playlists would be
  /// 700 KB. The cap counts entries rather than bytes because a byte budget means
  /// weighing every write, and being roughly right about a number that is easy to
  /// explain beats being exactly right about one that is not.
  final int maxEvictableEntries;

  final DateTime Function() _now;

  /// The payload stored under [key], or null if there is nothing usable there.
  ///
  /// Every failure is a miss rather than an exception. A cache that can throw
  /// puts the caller in the position of handling a storage problem on top of the
  /// network problem it was already handling, and there is nothing useful it
  /// could do differently.
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

  /// Stores [data] under [key], stamped with now.
  ///
  /// [evictable] entries are subject to [maxEvictableEntries]; the default is to
  /// keep an entry until it ages out, which is right for the fixed keys and
  /// would be a slow leak for anything else. See [maxEvictableEntries].
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

  /// Records [key] as the most recently written evictable entry, and drops the
  /// oldest ones past the cap.
  ///
  /// Recency here means *written*, not read. Bumping the order on a read would
  /// mean a disk write every time the cache is consulted, which is a strange
  /// price to pay for having avoided a network call -- and the thing being
  /// ordered is a set of album pages, where "opened again recently" and "fetched
  /// again recently" are nearly the same event anyway.
  Future<void> _track(String key) async {
    final tracked = await _index();
    tracked
      // Moved to the back rather than left where it was: the front of the list
      // is what gets deleted, so position is the whole point of the index.
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
