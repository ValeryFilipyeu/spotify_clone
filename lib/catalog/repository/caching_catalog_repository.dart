import 'dart:async';

import '../models/catalog_detail.dart';
import '../models/catalog_item.dart';
import '../models/catalog_section.dart';
import '../models/search_results.dart';
import 'catalog_repository.dart';

/// Remembers what the wrapped catalog answered, for [ttl].
///
/// A decorator rather than a feature of the API-backed repository, because
/// caching is not something the catalog *is*, it is something done to it: the
/// Audius implementation stays a plain translation of an HTTP API, the fake
/// stays a plain list, and either can be wrapped or not at the composition
/// point.
///
/// What it is actually for is **pushed routes**, chiefly opening a playlist.
/// A detail route is pushed and popped, so its cubit is disposed on the way back
/// and rebuilt on the way in: opening the same playlist twice fetched it twice,
/// and opening it from Home and then from Library fetched it twice again.
/// Repeated searches are the same story.
///
/// It is explicitly *not* for tab switching, which was the assumption this
/// started from and which measurement contradicted. The tabs are a
/// `StatefulShellRoute.indexedStack`, so each branch keeps a live Navigator and
/// Home's cubit survives the whole session -- it loads once whether or not this
/// class exists. Both facts are pinned by tests in `test/app_shell_test.dart`,
/// including the no-cache controls, so the next person does not have to guess
/// which screens this helps.
///
/// [ApiClient] already de-duplicates requests, but only those *in flight at the
/// same moment*; once one completes there is nothing left to join. That covers
/// a screen firing several requests at once, and does nothing for coming back a
/// few seconds later.
class CachingCatalogRepository implements CatalogRepository {
  CachingCatalogRepository(
    this._source, {
    this._ttl = const Duration(minutes: 5),
    this._maxEntries = 64,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final CatalogRepository _source;

  /// How long an answer stays usable.
  ///
  /// Minutes, not seconds: what is behind these calls is a trending list and
  /// some playlists, which do not change while someone is looking at them. Long
  /// enough that moving around the app is free, short enough that a session
  /// lasting an afternoon is not looking at breakfast's data.
  final Duration _ttl;

  /// A ceiling on remembered answers, because two of the keys are unbounded:
  /// there is one entry per playlist opened and one per search typed, and a
  /// cache with no cap is a memory leak with good intentions.
  final int _maxEntries;

  /// Injected so tests can move time instead of sleeping through a TTL.
  final DateTime Function() _now;

  /// Keyed by call. Dart preserves insertion order and a hit is re-inserted, so
  /// the first key is always the least recently used -- an LRU without needing
  /// a linked list to implement one.
  final Map<String, _CacheEntry> _entries = {};

  @override
  Future<List<CatalogSection>> fetchHomeSections() => _cached('home', _source.fetchHomeSections);

  @override
  Future<CatalogDetail> fetchDetail(String itemId) =>
      _cached('detail:$itemId', () => _source.fetchDetail(itemId));

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) {
    if (ids.isEmpty) return _source.fetchItemsByIds(ids);
    return _cached(_idsKey('items', ids), () => _source.fetchItemsByIds(ids));
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) {
    if (ids.isEmpty) return _source.fetchTracksByIds(ids);
    return _cached(_idsKey('tracks', ids), () => _source.fetchTracksByIds(ids));
  }

  @override
  Future<SearchResults> search(String query) {
    final needle = query.trim();
    // A blank query is answered without a request; caching it would only take
    // up one of the entries something else could use.
    if (needle.isEmpty) return _source.search(query);
    return _cached('search:${needle.toLowerCase()}', () => _source.search(query));
  }

  /// Forgets everything, not just the screen that asked.
  ///
  /// Coarse on purpose. Someone pulling to refresh is telling us the data on
  /// screen looks wrong, and the parts of it that are wrong are exactly the
  /// parts we cannot identify from here -- a playlist whose tracklist changed is
  /// invisible to Home's row. Clearing the lot costs a few requests that the
  /// user explicitly asked for.
  @override
  void invalidate() => _entries.clear();

  /// De-duplicated and sorted, so the same set of ids in a different order is
  /// the same key. The callers build these sets by iterating a liked or
  /// recently-played collection, and neither promises an order.
  String _idsKey(String prefix, Iterable<String> ids) {
    final sorted = ids.toSet().toList()..sort();
    return '$prefix:${sorted.join(',')}';
  }

  /// Returns the remembered answer for [key], or runs [fetch] and remembers it.
  ///
  /// Stores the *future* rather than waiting for a value, which makes a second
  /// caller arriving mid-flight join the first instead of starting its own.
  Future<T> _cached<T>(String key, Future<T> Function() fetch) {
    final hit = _entries[key];
    if (hit != null && _now().difference(hit.storedAt) < _ttl) {
      // Re-insert to move it to the back of the queue: it was just used, so it
      // should be the last thing evicted.
      _entries
        ..remove(key)
        ..[key] = hit;
      // Safe: the only writer is this method, and it always stores the future
      // returned by the fetch registered under this key.
      return hit.value as Future<T>;
    }

    final future = fetch();
    _entries
      ..remove(key)
      ..[key] = _CacheEntry(future, _now());

    // A failure must not be remembered for the next five minutes -- that would
    // turn one dropped connection into a screen that stays broken and cannot be
    // retried. Handled here rather than left to the caller, whose own error
    // handling does not know a cache exists.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          // Only if it is still the same entry: a later fetch may already have
          // replaced it, and evicting that one would discard a good answer.
          if (identical(_entries[key]?.value, future)) _entries.remove(key);
        },
      ),
    );

    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return future;
  }
}

class _CacheEntry {
  const _CacheEntry(this.value, this.storedAt);

  /// The in-flight or completed call. Kept as a future so concurrent callers
  /// share one round trip.
  final Future<Object?> value;

  final DateTime storedAt;
}
