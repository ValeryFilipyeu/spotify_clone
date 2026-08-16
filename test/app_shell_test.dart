import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/app.dart';
import 'package:spotify_clone/auth/repository/fake_auth_repository.dart';
import 'package:spotify_clone/auth/repository/session_storage.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/repository/caching_catalog_repository.dart';
import 'package:spotify_clone/history/repository/local_play_history_repository.dart';
import 'package:spotify_clone/likes/repository/local_likes_repository.dart';
import 'package:spotify_clone/player/repository/local_playback_settings_repository.dart';
import 'package:spotify_clone/storage/key_value_store.dart';

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

/// The hardcoded catalog, counting how often the home rows were asked for.
class _CountingCatalog extends FakeCatalogRepository {
  int homeLoads = 0;
  final Map<String, int> detailLoads = {};

  @override
  Future<List<CatalogSection>> fetchHomeSections() {
    homeLoads++;
    return super.fetchHomeSections();
  }

  @override
  Future<CatalogDetail> fetchDetail(String itemId) {
    detailLoads.update(itemId, (n) => n + 1, ifAbsent: () => 1);
    return super.fetchDetail(itemId);
  }
}

/// Boots straight into the authenticated shell with [catalog] behind it.
Future<FakeAuthRepository> pumpShell(WidgetTester tester, CatalogRepository catalog) async {
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
}
