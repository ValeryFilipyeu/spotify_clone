import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/app.dart';
import 'package:spotify_clone/auth/repository/fake_auth_repository.dart';
import 'package:spotify_clone/auth/repository/session_storage.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/repository/caching_catalog_repository.dart';
import 'package:spotify_clone/catalog/repository/offline/catalog_cache_store.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_catalog_repository.dart';
import 'package:spotify_clone/network/api_failure.dart';
import 'package:spotify_clone/history/repository/local_play_history_repository.dart';
import 'package:spotify_clone/likes/repository/local_likes_repository.dart';
import 'package:spotify_clone/player/repository/local_playback_settings_repository.dart';
import 'package:spotify_clone/storage/key_value_store.dart';

import 'helpers/fake_offline_status.dart';
import 'player/fake_audio_controller.dart';

/// In-memory SessionStorage so the test never touches a platform channel.
class _InMemorySessionStorage implements SessionStorage {
  _InMemorySessionStorage([Map<String, String>? seed]) : _store = {...?seed};

  final Map<String, String> _store;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

/// In-memory KeyValueStore so likes never touch shared_preferences' channel.
class _InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

/// The hardcoded catalog, counting how often the home rows were asked for -- and
/// able to stop answering, which is what a device with no network looks like from
/// above the repository.
class _CountingCatalog extends FakeCatalogRepository {
  int homeLoads = 0;
  final Map<String, int> detailLoads = {};

  /// Thrown by every call while set. An [ApiFailure] specifically: the offline
  /// layer decides what to do from the *type* of the failure, so a plain
  /// Exception here would exercise the wrong branch.
  ApiFailure? failure;

  Never get _fail => throw failure!;

  @override
  Future<List<CatalogSection>> fetchHomeSections() {
    homeLoads++;
    if (failure != null) _fail;
    return super.fetchHomeSections();
  }

  @override
  Future<CatalogDetail> fetchDetail(String itemId) {
    detailLoads.update(itemId, (n) => n + 1, ifAbsent: () => 1);
    if (failure != null) _fail;
    return super.fetchDetail(itemId);
  }

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) {
    if (failure != null && ids.isNotEmpty) _fail;
    return super.fetchItemsByIds(ids);
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) {
    if (failure != null && ids.isNotEmpty) _fail;
    return super.fetchTracksByIds(ids);
  }
}

/// Boots straight into the authenticated shell with [catalog] behind it.
Future<FakeAuthRepository> pumpShell(
  WidgetTester tester,
  CatalogRepository catalog, {
  OfflineStatus? offlineStatus,
}) async {
  final storage = _InMemorySessionStorage({'auth_session_email': 'test@spotify.com'});
  final repository = FakeAuthRepository(sessionStorage: storage);
  await repository.restoreSession();

  final store = _InMemoryKeyValueStore();
  await tester.pumpWidget(
    MyApp(
      authRepository: repository,
      likesRepository: LocalLikesRepository(store),
      playHistoryRepository: LocalPlayHistoryRepository(store),
      playbackSettingsRepository: LocalPlaybackSettingsRepository(store),
      audioController: FakeAudioController(),
      catalogRepository: catalog,
      // Left out entirely by default, which is the interesting half of the
      // default: MyApp falls back to AlwaysOnline, so every other test in this
      // suite also asserts that the strip stays out of the way.
      offlineStatus: offlineStatus ?? const AlwaysOnline(),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('an authenticated session boots into the tab shell and switches tabs', (
    tester,
  ) async {
    // Seed a restored session for the seeded demo account so the app boots
    // straight into the authenticated shell (bypassing the login flow).
    final storage = _InMemorySessionStorage({'auth_session_email': 'test@spotify.com'});
    final repository = FakeAuthRepository(sessionStorage: storage);
    await repository.restoreSession();

    final store = _InMemoryKeyValueStore();
    await tester.pumpWidget(
      MyApp(
        authRepository: repository,
        likesRepository: LocalLikesRepository(store),
        playHistoryRepository: LocalPlayHistoryRepository(store),
        playbackSettingsRepository: LocalPlaybackSettingsRepository(store),
        audioController: FakeAudioController(),
      ),
    );
    await tester.pumpAndSettle();

    // The three tab destinations are present (this is the shell chrome).
    expect(find.widgetWithText(NavigationBar, 'Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // only the nav label so far
    expect(find.text('Library'), findsOneWidget);

    // Switch to Search -> its (lazily built) screen appears.
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search songs, playlists and albums'), findsOneWidget);

    // Switch to Library -> its screen appears.
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Your Library'), findsOneWidget);

    await repository.close();
  });

  testWidgets('switching tabs does not reload the home rows', (tester) async {
    // Worth pinning, because it is easy to assume the opposite: each tab's cubit
    // is created in a BlocProvider scoped to its route, which sounds like
    // leaving the tab would dispose it. It does not. StatefulShellRoute.
    // indexedStack keeps one live Navigator per branch, so Home's route -- and
    // its cubit -- survives for the whole session and loads exactly once.
    //
    // No cache involved here. If this ever reports more than one, the shell has
    // stopped preserving branches and every tab switch became a network round
    // trip.
    final catalog = _CountingCatalog();
    final repository = await pumpShell(tester, catalog);

    await tapTab(tester, 'Search');
    await tapTab(tester, 'Home');
    await tapTab(tester, 'Library');
    await tapTab(tester, 'Home');

    expect(catalog.homeLoads, 1);

    await repository.close();
  });

  testWidgets('pulling down on Home refetches, cache or no cache', (tester) async {
    // End-to-end proof of the whole chain: the gesture reaches the cubit, the
    // cubit invalidates the cache, and the fetch actually goes through to the
    // source. Wrapped in the cache deliberately -- unwrapped, this would pass
    // even if invalidate() did nothing at all.
    final catalog = _CountingCatalog();
    final repository = await pumpShell(tester, CachingCatalogRepository(catalog));
    expect(catalog.homeLoads, 1);

    // `.first` is the vertical list. The section rows are ListViews too, and
    // they come after it in the tree because they are its children.
    await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(catalog.homeLoads, 2);
    // The rows are still there: a refresh replaces content, it does not blank it.
    expect(find.text('Made for you'), findsOneWidget);

    await repository.close();
  });

  group('reopening a playlist', () {
    /// Opens the first catalog card on Home, then comes back.
    Future<void> openAndClose(WidgetTester tester) async {
      await tester.tap(find.text('Daily Mix 1').first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    testWidgets('refetches it every time, with no cache', (tester) async {
      // Unlike a tab, a detail route really is pushed and popped, so its cubit
      // is disposed on the way back and rebuilt on the way in. This is the case
      // the cache is actually for.
      final catalog = _CountingCatalog();
      final repository = await pumpShell(tester, catalog);

      await openAndClose(tester);
      await openAndClose(tester);

      expect(catalog.detailLoads['dm1'], 2);

      await repository.close();
    });

    testWidgets('serves it from cache the second time', (tester) async {
      final catalog = _CountingCatalog();
      final repository = await pumpShell(tester, CachingCatalogRepository(catalog));

      await openAndClose(tester);
      await tester.tap(find.text('Daily Mix 1').first);
      await tester.pumpAndSettle();

      expect(catalog.detailLoads['dm1'], 1);
      // A real screen, not an empty one served from a stale entry.
      expect(find.text('Daily Mix 1'), findsWidgets);

      await repository.close();
    });
  });

  group('showing saved data', () {
    /// What the unit tests structurally cannot check: that the strip is actually
    /// wired into the app. OfflineBanner can be perfect and OfflineStatus can be
    /// reported perfectly while nothing puts the two in the same tree, and every
    /// test either side of this one would still pass.
    final notice = find.textContaining('offline');

    testWidgets('nothing is said while the catalog is answering', (tester) async {
      final repository = await pumpShell(tester, _CountingCatalog());

      expect(notice, findsNothing);

      await repository.close();
    });

    testWidgets('the shell says so, on every tab and inside a pushed album', (tester) async {
      final status = FakeOfflineStatus(offline: true);
      addTearDown(status.close);
      final repository = await pumpShell(tester, _CountingCatalog(), offlineStatus: status);

      expect(notice, findsOneWidget);

      // One insertion point is meant to cover all of this. The tabs are branches
      // of the same shell and an album opens *inside* a branch, so the strip
      // should survive both without being mentioned anywhere else.
      await tapTab(tester, 'Library');
      expect(notice, findsOneWidget);

      await tapTab(tester, 'Home');
      await tester.tap(find.text('Daily Mix 1').first);
      await tester.pumpAndSettle();
      expect(find.text('Daily Mix 1'), findsWidgets, reason: 'the album really did open');
      expect(notice, findsOneWidget);

      await repository.close();
    });

    testWidgets('it appears without a reload when the network drops mid-session', (tester) async {
      final status = FakeOfflineStatus();
      addTearDown(status.close);
      final repository = await pumpShell(tester, _CountingCatalog(), offlineStatus: status);
      expect(notice, findsNothing);

      status.flip(offline: true);
      // Two frames: the first delivers the event to the StreamBuilder, whose
      // setState lands after that frame was drawn, and the second renders it.
      await tester.pump();
      await tester.pump();

      expect(notice, findsOneWidget);

      await repository.close();
    });
  });

  group('with nothing to reach', () {
    /// The story the whole offline layer exists for, told through the real chain
    /// instead of a fake repository. Everything else in the suite stops at one of
    /// the seams; these two go from a gesture to a screen.
    final notice = find.textContaining('offline');
    final unreachable = NetworkUnreachable(Uri.parse('https://api.audius.co/v1'), 'no network');

    /// The app as main() builds it, minus the part that talks to Audius.
    ({OfflineCatalogRepository catalog, _CountingCatalog source}) app(KeyValueStore device) {
      final source = _CountingCatalog();
      final catalog = OfflineCatalogRepository.chain(source, store: CatalogCacheStore(device));
      addTearDown(catalog.close);
      return (catalog: catalog, source: source);
    }

    testWidgets('a refresh with no network keeps the rows and explains itself', (tester) async {
      final (catalog: catalog, source: source) = app(_InMemoryKeyValueStore());
      final auth = await pumpShell(tester, catalog, offlineStatus: catalog);
      expect(find.text('Made for you'), findsOneWidget);
      expect(notice, findsNothing);

      source.failure = unreachable;
      await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // Not an error page. The gesture cleared the memory cache, the fetch failed,
      // and the saved copy answered instead -- so the screen the user was reading
      // is still there.
      expect(find.text('Made for you'), findsOneWidget);
      expect(notice, findsOneWidget);
      // The wart, pinned rather than left to be discovered: from the refresh's own
      // point of view this *worked*, so it says nothing. The strip is what carries
      // the news.
      expect(find.textContaining('Could not refresh'), findsNothing);

      await auth.close();
    });

    testWidgets('a cold start with no network shows what the last one saved', (tester) async {
      // The one thing an in-memory cache structurally cannot do, and the reason
      // there is a disk layer at all. The store outlives the app around it, exactly
      // as shared_preferences does.
      final device = _InMemoryKeyValueStore();

      final first = app(device);
      final firstAuth = await pumpShell(tester, first.catalog, offlineStatus: first.catalog);
      expect(find.text('Made for you'), findsOneWidget);
      await firstAuth.close();

      // Torn down for real. Pumping another MyApp straight away would update the
      // existing element tree in place and the old HomeCubit would survive, which
      // would make this test pass whether or not anything was ever saved.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final second = app(device);
      second.source.failure = unreachable;
      final secondAuth = await pumpShell(tester, second.catalog, offlineStatus: second.catalog);

      expect(second.source.homeLoads, 1, reason: 'it did try the network first');
      expect(find.text('Made for you'), findsOneWidget);
      expect(notice, findsOneWidget);

      await secondAuth.close();
    });

    testWidgets('a first ever launch with no network has to admit it', (tester) async {
      // Nothing saved, nothing to serve. The error screen is the honest answer, and
      // an empty catalog dressed up as a successful load would not be.
      final (catalog: catalog, source: source) = app(_InMemoryKeyValueStore());
      source.failure = unreachable;
      final auth = await pumpShell(tester, catalog, offlineStatus: catalog);

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Made for you'), findsNothing);
      expect(notice, findsOneWidget);

      await auth.close();
    });
  });
}
