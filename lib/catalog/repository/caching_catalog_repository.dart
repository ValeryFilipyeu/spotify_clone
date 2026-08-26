import 'dart:async';

import '../models/catalog_detail.dart';
import '../models/catalog_item.dart';
import '../models/catalog_section.dart';
import '../models/search_results.dart';
import 'catalog_repository.dart';

/// Remembers what the wrapped catalog answered, for [_ttl].
///
/// This is for **pushed routes**, chiefly opening a playlist: a detail route is
/// popped and its cubit disposed, so opening the same playlist twice used to
/// fetch it twice. Repeated searches likewise.
///
/// It is *not* for tab switching, which was the original assumption and is wrong:
/// the tabs are an `indexedStack`, so Home's cubit survives the whole session and
/// loads once either way. Both facts are pinned in `test/app_shell_test.dart`.
///
/// [ApiClient] de-duplicates too, but only requests in flight at the same moment
/// -- which does nothing for coming back a few seconds later.
class CachingCatalogRepository implements CatalogRepository {
  CachingCatalogRepository(
    this._source, {
    this._ttl = const Duration(minutes: 5),
    this._maxEntries = 64,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final CatalogRepository _source;

  /// How long an answer stays usable. Minutes, not seconds: trending lists do
  /// not change while someone is looking at them.
  final Duration _ttl;

  /// A ceiling, because two keys are unbounded: one entry per playlist opened
  /// and one per search typed.
  final int _maxEntries;

  /// Injected so tests can move time instead of sleeping through a TTL.
  final DateTime Function() _now;

  /// Keyed by call. Dart preserves insertion order and hits are re-inserted, so
  /// the first key is the least recently used -- an LRU with no linked list.
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
    if (needle.isEmpty) return _source.search(query);
    return _cached('search:${needle.toLowerCase()}', () => _source.search(query));
  }

  /// Forgets everything, not just the screen that asked: the wrong parts are
  /// exactly the parts this cannot identify from here.
  ///
  /// Forwarded as well as handled. Nothing below remembers anything today, which
  /// is why the forwarding has to be written down rather than noticed later.
  @override
  void invalidate() {
    _entries.clear();
    _source.invalidate();
  }

  /// Sorted and de-duplicated: callers iterate collections that promise no
  /// order, and the same ids should be the same key.
  String _idsKey(String prefix, Iterable<String> ids) {
    final sorted = ids.toSet().toList()..sort();
    return '$prefix:${sorted.join(',')}';
  }

  /// The remembered answer for [key], or [fetch] run and remembered. Stores the
  /// *future*, so a caller arriving mid-flight joins instead of starting its own.
  Future<T> _cached<T>(String key, Future<T> Function() fetch) {
    final hit = _entries[key];
    if (hit != null && _now().difference(hit.storedAt) < _ttl) {
      // To the back of the queue: just used, so last to be evicted.
      _entries
        ..remove(key)
        ..[key] = hit;
      // Safe: this method is the only writer and always stores the fetch's own
      // future under its key.
      return hit.value as Future<T>;
    }

    final future = fetch();
    _entries
      ..remove(key)
      ..[key] = _CacheEntry(future, _now());

    // Never remember a failure: one dropped connection would become a screen
    // that stays broken for the whole TTL.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          // Only if still the same entry; a later fetch may have replaced it.
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

  /// A future, so concurrent callers share one round trip.
  final Future<Object?> value;

  final DateTime storedAt;
}
