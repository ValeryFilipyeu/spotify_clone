import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/app.dart';
import 'package:spotify_clone/auth/repository/fake_auth_repository.dart';
import 'package:spotify_clone/auth/repository/session_storage.dart';
import 'package:spotify_clone/likes/repository/local_likes_repository.dart';
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

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('an authenticated session boots into the tab shell and switches tabs', (tester) async {
    // Seed a restored session for the seeded demo account so the app boots
    // straight into the authenticated shell (bypassing the login flow).
    final storage = _InMemorySessionStorage({'auth_session_email': 'test@spotify.com'});
    final repository = FakeAuthRepository(sessionStorage: storage);
    await repository.restoreSession();

    await tester.pumpWidget(MyApp(
      authRepository: repository,
      likesRepository: LocalLikesRepository(_InMemoryKeyValueStore()),
      audioController: FakeAudioController(),
    ));
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
}
