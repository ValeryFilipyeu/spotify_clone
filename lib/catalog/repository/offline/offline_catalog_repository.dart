import 'dart:async';

import '../../../network/api_failure.dart';
import '../../models/catalog_detail.dart';
import '../../models/catalog_item.dart';
import '../../models/catalog_section.dart';
import '../../models/search_results.dart';
import '../caching_catalog_repository.dart';
import '../catalog_repository.dart';
import 'catalog_cache_store.dart';
import 'catalog_json.dart';
import 'offline_status.dart';

/// Keeps what the catalog answered on the device, and serves it when the catalog
/// cannot be reached.
///
/// A decorator, like [CachingCatalogRepository], and for the same reason: the
/// Audius implementation stays a plain translation of an HTTP API and has no idea
/// any of this is happening. What it adds is the part an in-memory cache
/// structurally cannot -- surviving the process. A cold start in a tunnel has an
/// empty memory cache by definition, and that is the exact moment a music app is
/// either useful or a spinner.
///
/// ## The rule
///
/// **The network is always asked first.** This is not a read-through cache, and
/// making it one would be the obvious mistake: it would show yesterday's home
/// screen to someone with five bars of signal. A saved answer is served in one
/// situation only, which is that the live one could not be had.
///
/// "Could not be had" is a narrower claim than "the request failed", and telling
/// the two apart is what [ApiFailure] being sealed is for -- see [_meansUnreachable].
/// A 404 is a real answer and the truth is that the album is gone; serving a
/// saved copy over the top of it would hide the one useful fact in the exchange.
///
/// ## Where it sits in the chain
///
/// Outside the in-memory cache:
///
/// ```dart
/// OfflineCatalogRepository(CachingCatalogRepository(AudiusCatalogRepository(...)))
/// ```
///
/// The other way round works and is worse. A fallback served from *inside* the
/// memory cache is remembered by it for the whole TTL, so the banner stays up and
/// the saved copy keeps being served for minutes after the network came back --
/// the app recovers on a timer instead of on the facts. Out here, a fallback is
/// remembered by nobody, so the next read genuinely retries.
///
/// The price of that is repeated failures while offline, which is what
/// [retryAfter] is for. The cost of this position that is simply accepted: a
/// memory-cache hit is written to disk again, since from out here a hit and a
/// fetch are indistinguishable. Both are a `setString` into a map, so the waste
/// is real and negligible.
///
/// ## What it does not do
///
/// A pull-to-refresh while offline *succeeds*, quietly, out of the cache -- the
/// spinner retracts and nothing appears to have gone wrong. That is deliberate.
/// The alternative is an error over content that is perfectly fine to look at,
/// and the banner driven by [OfflineStatus] is already saying why nothing
/// changed. It is worth knowing about, because it is the one place where this
/// class makes a screen say something slightly untrue.
class OfflineCatalogRepository implements CatalogRepository, OfflineStatus {
  OfflineCatalogRepository(
    this._source, {
    required this._store,
    this.retryAfter = const Duration(seconds: 20),
    this.maxEntities = defaultMaxEntities,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// The whole chain the app runs: this layer, then the memory cache, then
  /// [source].
  ///
  /// A function rather than three lines in main(), because the order is a
  /// decision with consequences (see above) and one written down in a place a
  /// test can reach. Otherwise the argument for it lives only in a comment, and
  /// the day someone tidies main() by swapping two constructors, nothing objects.
  ///
  /// The return type is doing work too, and more of it than the test does.
  /// Handing back the concrete outer layer rather than a [CatalogRepository] is
  /// what lets main() pass the same object as the app's [OfflineStatus] -- so a
  /// chain assembled the other way round does not fail a test, it fails to
  /// compile.
  static OfflineCatalogRepository chain(
    CatalogRepository source, {
    required CatalogCacheStore store,
  }) => OfflineCatalogRepository(CachingCatalogRepository(source), store: store);

  /// See [maxEntities]. Named so the size measurements can assert against the
  /// number actually shipped.
  static const int defaultMaxEntities = 64;

  static const String _homeKey = 'home';
  static const String _itemsKey = 'items';
  static const String _hitsKey = 'tracks';

  static String _detailKey(String itemId) => 'detail:$itemId';

  final CatalogRepository _source;
  final CatalogCacheStore _store;

  /// How long one failure speaks for the ones that would have followed it.
  ///
  /// A circuit breaker, and the thing that makes asking the network first
  /// affordable. Without it, every screen opened while offline waits out its own
  /// full timeout before falling back -- ten seconds per navigation on a dead
  /// wifi network, which reads as an app that is broken rather than one that is
  /// offline. With it, the first read pays that and the rest are answered from
  /// disk immediately.
  ///
  /// Twenty seconds, from both ends: long enough that a burst of navigation
  /// shares one verdict, short enough that a network coming back is noticed
  /// before anyone has decided the app is stuck. A pull-to-refresh closes it
  /// early regardless -- see [invalidate].
  ///
  /// Note it only short-circuits reads that *have* a saved answer. A search, or
  /// an album never opened before, still goes to the network however recently
  /// something else failed: there is nothing to serve instead, so skipping the
  /// attempt would turn "probably offline" into a guaranteed error.
  final Duration retryAfter;

  /// The ceiling on remembered items and, separately, tracks.
  ///
  /// The two bulk lookups are cached per entity rather than per call (see
  /// [encodeItemsById]), so this counts things rather than questions.
  ///
  /// Sixty-four of each, which is more than most Libraries hold and, measured on
  /// real payloads, 37 KB of items plus 73 KB of track hits -- a hit being the
  /// heaviest thing in the cache, since it carries a whole stand-in album
  /// alongside its track. See `catalog_cache_size_test.dart`; the numbers are why
  /// this is 64 and not the 128 it started as.
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
      // An empty list is not an answer: Home would take it for a successful load
      // of a catalog with nothing in it and draw an empty screen with no
      // explanation. Better to let the network's failure stand and show the
      // retry.
      return sections.isEmpty ? null : sections;
    },
  );

  @override
  Future<CatalogDetail> fetchDetail(String itemId) {
    final key = _detailKey(itemId);
    return _guard(
      fetch: () => _source.fetchDetail(itemId),
      // The only unbounded key: one per album ever opened.
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
    // No request is made for an empty set, so there is nothing to save and
    // nothing a failure could fall back on.
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

  /// Searched live or not at all.
  ///
  /// Two reasons, and either would be enough. The key space is unbounded -- one
  /// entry per phrase anyone ever typed -- and, more to the point, a search is a
  /// question about the *whole* catalog, which a few saved pages cannot answer.
  /// Serving "no results" out of a cache that simply does not contain the answer
  /// is a wrong answer, not a degraded one.
  ///
  /// It still reports what it learned: a search is often the first thing tapped
  /// after a network comes back, and it is the one call here that can clear the
  /// banner without anything else having to reload.
  @override
  Future<SearchResults> search(String query) async {
    // Answered without a request, so it says nothing about reachability.
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

  /// Discards the memory cache below and re-arms the network. Pointedly leaves
  /// what is on disk alone.
  ///
  /// Clearing the saved copy here would be exactly backwards. A pull-to-refresh
  /// is most likely to be *used* when the screen looks wrong, which is most
  /// likely to be when the connection is bad -- so wiping the fallback is a
  /// feature that deletes your offline library at the precise moment you need it
  /// and hands you an error page instead. Stale entries age out on their own (see
  /// [CatalogCacheStore.maxAge]) and a successful fetch overwrites them anyway.
  ///
  /// What it does do is close the breaker: the gesture is a person explicitly
  /// asking to try the network, which outranks a verdict reached fifteen seconds
  /// ago.
  @override
  void invalidate() {
    _failedAt = null;
    _source.invalidate();
  }

  /// Releases the change stream.
  ///
  /// The app never calls it -- the catalog outlives every screen that reads from
  /// it -- but a test that builds one per case would otherwise leave a controller
  /// open behind each.
  void close() => _changes.close();

  /// Runs [fetch], saving what comes back and falling back to what was saved
  /// last time if it could not be reached.
  Future<T> _guard<T>({
    required Future<T> Function() fetch,
    required Future<void> Function(T value) save,
    required Future<T?> Function() recover,
  }) async {
    // Something failed a moment ago and there is a usable answer on disk: use it
    // rather than waiting out another timeout to learn the same thing.
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
      // Nothing saved: the failure is the only answer there is, and it is the
      // caller's to handle. Deliberately not an empty list -- "we could not ask"
      // and "there is nothing" look identical on screen and mean opposite
      // things.
      if (saved == null) rethrow;
      return saved;
    }
  }

  /// Whether a failure means the catalog could not be *reached*, as opposed to
  /// having been reached and disagreed with.
  ///
  /// The payoff for [ApiFailure] being sealed: the switch has no default branch,
  /// so a fifth failure mode added later does not compile until someone decides
  /// which side of this line it falls on. Getting that wrong in either direction
  /// is a real bug -- too eager and a deleted album keeps reappearing from the
  /// cache, too strict and a train journey shows four error screens.
  bool _meansUnreachable(Object error) {
    // Not an ApiFailure at all: a CatalogItemNotFound, or a bug. Neither is
    // evidence about the network, and a cache must never paper over a bug.
    if (error is! ApiFailure) return false;

    return switch (error) {
      NetworkUnreachable() || RequestTimeout() => true,
      // A 500 or a 429 is a server that momentarily cannot answer, which is the
      // same situation as an unreachable one from here. A 4xx is an answer.
      HttpErrorStatus(:final isTransient) => isTransient,
      // The server answered and we could not read it. Retrying will not fix that
      // and a saved copy would hide a parsing bug behind stale data.
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
    // Re-stamped on every failure, so a long outage keeps the breaker open
    // without needing a second mechanism to hold it there.
    _failedAt = _now();
    _emit(true);
  }

  void _emit(bool offline) {
    if (_offline == offline) return;
    _offline = offline;
    if (!_changes.isClosed) _changes.add(offline);
  }

  /// Merges [fresh] into the collection at [key], newest last, capped at
  /// [maxEntities].
  ///
  /// Merged rather than replaced because the two callers ask different questions
  /// of the same collection: Home resolves a few recently-played ids and Library
  /// resolves everything liked. Replacing would let each evict the other's work
  /// on every visit.
  Future<void> _merge(String key, Map<String, Object?> fresh) async {
    final saved = await _store.read(key) ?? const <String, Object?>{};
    final merged = <String, Object?>{
      // Anything freshly fetched is dropped here and re-added below, so it ends
      // up at the back: insertion order is the eviction order.
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
  /// none of them.
  ///
  /// A partial answer is returned rather than withheld, because both bulk methods
  /// already promise to drop ids they have nothing for -- so half a Library is a
  /// valid response to this interface, and a better one than an error page.
  /// Holding *none* of them is different: that is no answer at all, and the
  /// caller should hear about the failure instead.
  /// [T] is bound to [Object] rather than left open so that `nonNulls` below
  /// resolves against `Iterable<T?>`; with an unbounded T it matches
  /// `Iterable<Object?>` instead and the result comes back as `List<Object>`.
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

  /// Reads the fallback, treating any problem with it as "nothing saved".
  ///
  /// A payload written by an older build, or half-written by a process that died,
  /// must not replace the network error the caller is about to be told about with
  /// a parse error from the cache. The first is actionable; the second is noise
  /// from a layer the caller does not know exists.
  Future<T?> _recoverQuietly<T>(Future<T?> Function() recover) async {
    try {
      return await recover();
    } on Object {
      return null;
    }
  }

  /// Saves, and never fails a good fetch because saving it did not work.
  ///
  /// A full disk or a store that has gone away is a reason to have no cache, not
  /// a reason for the screen to show an error over data it is holding.
  Future<void> _saveQuietly(Future<void> Function() save) async {
    try {
      await save();
    } on Object {
      // Nothing to do and nobody to tell: the next successful fetch tries again.
    }
  }
}
