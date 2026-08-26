import 'dart:async';

import '../../../network/api_failure.dart';
import '../../models/catalog_detail.dart';
import '../../models/catalog_json.dart';
import '../../models/catalog_item.dart';
import '../../models/catalog_section.dart';
import '../../models/search_results.dart';
import '../caching_catalog_repository.dart';
import '../catalog_repository.dart';
import 'catalog_cache_store.dart';
import 'offline_status.dart';

/// Keeps what the catalog answered on the device and serves it when the catalog
/// cannot be reached.
///
/// **The network is always asked first** -- this is not a read-through cache. A
/// saved answer is served only when the live one could not be had, which is a
/// narrower thing than "the request failed": a 404 is a real answer and hiding it
/// behind a saved copy would lose the only useful fact in the exchange. See
/// [_meansUnreachable].
///
/// Sits *outside* the memory cache: `Offline(Caching(Audius(...)))`. Inverted, a
/// fallback would be remembered for the whole TTL and the app would recover on a
/// timer instead of on the facts. The cost of this position is that a memory-cache
/// hit is written to disk again, which is a map write and worth ignoring.
///
/// One known wart: a pull-to-refresh while offline succeeds quietly out of the
/// cache. Better than an error over content that is fine to look at, and the
/// banner already says why nothing changed.
class OfflineCatalogRepository implements CatalogRepository, OfflineStatus {
  OfflineCatalogRepository(
    this._source, {
    required this._store,
    this.retryAfter = const Duration(seconds: 20),
    this.maxEntities = defaultMaxEntities,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// The whole chain the app runs, assembled here rather than in main() so the
  /// order cannot be tidied away.
  ///
  /// Returning the concrete outer layer is deliberate: main() needs it as the
  /// app's [OfflineStatus], so a chain built the other way round does not fail a
  /// test, it fails to compile.
  static OfflineCatalogRepository chain(
    CatalogRepository source, {
    required CatalogCacheStore store,
  }) => OfflineCatalogRepository(CachingCatalogRepository(source), store: store);

  /// Named so the size measurements can assert against the shipped number.
  static const int defaultMaxEntities = 64;

  static const String _homeKey = 'home';
  static const String _itemsKey = 'items';
  static const String _hitsKey = 'tracks';

  static String _detailKey(String itemId) => 'detail:$itemId';

  final CatalogRepository _source;
  final CatalogCacheStore _store;

  /// A circuit breaker: how long one failure speaks for the ones that would have
  /// followed. Without it every screen opened offline waits out its own timeout,
  /// which reads as a broken app rather than an offline one.
  ///
  /// Only short-circuits reads that *have* a saved answer -- a search or an
  /// unseen album still goes to the network, since skipping it would turn
  /// "probably offline" into a guaranteed error. [invalidate] closes it early.
  final Duration retryAfter;

  /// Ceiling on remembered items and, separately, tracks. Cached per entity
  /// rather than per call, so this counts things rather than questions.
  ///
  /// 64 each measures 37 KB of items plus 73 KB of track hits on real payloads,
  /// which is why it is not the 128 it started as. See
  /// `catalog_cache_size_test.dart`.
  final int maxEntities;

  final DateTime Function() _now;

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  bool _offline = false;

  /// When the last unreachable failure happened, or null if the breaker is
  /// closed.
  DateTime? _failedAt;

  @override
  bool get isOffline => _offline;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<List<CatalogSection>> fetchHomeSections() => _guard(
    fetch: _source.fetchHomeSections,
    save: (sections) => _store.write(_homeKey, encodeSections(sections)),
    recover: () async {
      final saved = await _store.read(_homeKey);
      if (saved == null) return null;
      final sections = decodeSections(saved);
      // Home would draw an empty list as a successful load of an empty catalog.
      return sections.isEmpty ? null : sections;
    },
  );

  @override
  Future<CatalogDetail> fetchDetail(String itemId) {
    final key = _detailKey(itemId);
    return _guard(
      fetch: () => _source.fetchDetail(itemId),
      save: (detail) => _store.write(key, encodeDetail(detail), evictable: true),
      recover: () async {
        final saved = await _store.read(key);
        return saved == null ? null : decodeDetail(saved);
      },
    );
  }

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return _source.fetchItemsByIds(wanted);

    return _guard(
      fetch: () => _source.fetchItemsByIds(wanted),
      save: (items) => _merge(_itemsKey, encodeItemsById(items)),
      recover: () => _recall(_itemsKey, wanted, decodeItemsById),
    );
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return _source.fetchTracksByIds(wanted);

    return _guard(
      fetch: () => _source.fetchTracksByIds(wanted),
      save: (hits) => _merge(_hitsKey, encodeHitsById(hits)),
      recover: () => _recall(_hitsKey, wanted, decodeHitsById),
    );
  }

  /// Searched live or not at all: a search asks about the *whole* catalog, and
  /// "no results" out of a few saved pages is a wrong answer, not a degraded one.
  ///
  /// It still reports what it learned, since a search is often the first thing
  /// tapped when a network comes back.
  @override
  Future<SearchResults> search(String query) async {
    if (query.trim().isEmpty) return _source.search(query);

    try {
      final results = await _source.search(query);
      _markOnline();
      return results;
    } on Object catch (error) {
      if (_meansUnreachable(error)) _markOffline();
      rethrow;
    }
  }

  /// Discards the memory cache and closes the breaker -- a person asking for the
  /// network outranks a verdict reached fifteen seconds ago.
  ///
  /// Leaves the disk alone deliberately: pull-to-refresh is used when the screen
  /// looks wrong, which is when the connection is bad, so wiping the fallback
  /// would delete the offline library exactly when it is needed.
  @override
  void invalidate() {
    _failedAt = null;
    _source.invalidate();
  }

  /// For tests. The app never calls it: the catalog outlives every screen.
  void close() => _changes.close();

  /// Runs [fetch], saving what comes back and falling back to what was saved
  /// last time if it could not be reached.
  Future<T> _guard<T>({
    required Future<T> Function() fetch,
    required Future<void> Function(T value) save,
    required Future<T?> Function() recover,
  }) async {
    // Something just failed and there is a usable answer on disk.
    if (_breakerIsOpen) {
      final saved = await _recoverQuietly(recover);
      if (saved != null) return saved;
    }

    try {
      final value = await fetch();
      _markOnline();
      await _saveQuietly(() => save(value));
      return value;
    } on Object catch (error) {
      if (!_meansUnreachable(error)) rethrow;
      _markOffline();

      final saved = await _recoverQuietly(recover);
      // Not an empty list: "we could not ask" and "there is nothing" look the
      // same on screen and mean opposite things.
      if (saved == null) rethrow;
      return saved;
    }
  }

  /// Whether the catalog could not be *reached*, as opposed to reached and
  /// disagreed with.
  ///
  /// No default branch, so a new [ApiFailure] does not compile until someone
  /// places it: too eager and deleted albums reappear, too strict and a train
  /// journey is four error screens.
  bool _meansUnreachable(Object error) {
    // A CatalogItemNotFound, or a bug. Neither is evidence about the network.
    if (error is! ApiFailure) return false;

    return switch (error) {
      NetworkUnreachable() || RequestTimeout() => true,
      // 5xx/429 cannot answer right now; a 4xx is an answer.
      HttpErrorStatus(:final isTransient) => isTransient,
      // A saved copy would hide a parsing bug behind stale data.
      MalformedResponse() => false,
    };
  }

  bool get _breakerIsOpen {
    final failedAt = _failedAt;
    return failedAt != null && _now().difference(failedAt) < retryAfter;
  }

  void _markOnline() {
    _failedAt = null;
    _emit(false);
  }

  void _markOffline() {
    // Re-stamped every failure, so a long outage holds the breaker open.
    _failedAt = _now();
    _emit(true);
  }

  void _emit(bool offline) {
    if (_offline == offline) return;
    _offline = offline;
    if (!_changes.isClosed) _changes.add(offline);
  }

  /// Merges [fresh] into the collection at [key], newest last, capped at
  /// [maxEntities]. Merged, not replaced: Home and Library ask different
  /// questions of the same collection and would evict each other.
  Future<void> _merge(String key, Map<String, Object?> fresh) async {
    final saved = await _store.read(key) ?? const <String, Object?>{};
    final merged = <String, Object?>{
      // Re-added below, so it lands at the back: insertion order is eviction
      // order.
      for (final entry in saved.entries)
        if (!fresh.containsKey(entry.key)) entry.key: entry.value,
      ...fresh,
    };

    while (merged.length > maxEntities) {
      merged.remove(merged.keys.first);
    }
    await _store.write(key, merged);
  }

  /// Whichever of [wanted] the collection at [key] holds, or null if it holds
  /// none. Partial is a valid answer here -- both bulk methods already drop ids
  /// they have nothing for -- but none at all is no answer, and the caller should
  /// hear about the failure.
  ///
  /// [T] is bound to [Object] so `nonNulls` resolves against `Iterable<T?>`.
  Future<List<T>?> _recall<T extends Object>(
    String key,
    Set<String> wanted,
    Map<String, T> Function(Map<String, Object?> json) decode,
  ) async {
    final saved = await _store.read(key);
    if (saved == null) return null;

    final entities = decode(saved);
    final found = [for (final id in wanted) entities[id]].nonNulls.toList();
    return found.isEmpty ? null : found;
  }

  /// Reads the fallback, treating any problem with it as "nothing saved" -- a
  /// stale payload must not replace the network error with a parse error from a
  /// layer the caller does not know exists.
  Future<T?> _recoverQuietly<T>(Future<T?> Function() recover) async {
    try {
      return await recover();
    } on Object {
      return null;
    }
  }

  /// A full disk is a reason to have no cache, not a reason to fail a fetch that
  /// worked.
  Future<void> _saveQuietly(Future<void> Function() save) async {
    try {
      await save();
    } on Object {
      // The next successful fetch tries again.
    }
  }
}
