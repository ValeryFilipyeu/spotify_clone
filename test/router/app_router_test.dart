import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/app.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/auth/repository/auth_repository.dart';
import 'package:spotify_clone/auth/repository/fake_auth_repository.dart';
import 'package:spotify_clone/auth/repository/session_storage.dart';
import 'package:spotify_clone/history/repository/local_play_history_repository.dart';
import 'package:spotify_clone/landing/view/landing_page.dart';
import 'package:spotify_clone/likes/repository/local_likes_repository.dart';
import 'package:spotify_clone/log_in/view/log_in_page.dart';
import 'package:spotify_clone/player/repository/local_playback_settings_repository.dart';
import 'package:spotify_clone/router/app_routes.dart';
import 'package:spotify_clone/sign_up/view/sign_up_page.dart';

import '../helpers/fake_key_value_store.dart';
import '../player/fake_audio_controller.dart';

const _email = 'test@spotify.com';
const _password = 'Password1';

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

/// Never answers, so the app stays in [AuthStatus.unknown] -- the cold-boot
/// window before a restored session is known either way. A real repository
/// leaves it in microseconds, which is exactly why it needs asking for
/// deliberately.
class _PendingAuthRepository implements AuthRepository {
  final StreamController<AppUser?> _controller = StreamController<AppUser?>.broadcast();

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  Future<void> signUp({required String email, required String password}) async {}

  @override
  Future<void> logIn({required String email, required String password}) async {}

  @override
  Future<void> logOut() async {}

  Future<void> close() => _controller.close();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpApp(WidgetTester tester, AuthRepository repository) async {
    final store = FakeKeyValueStore();
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
  }

  /// Boots the real app, signed in or not, and hands back the repository so a
  /// test can change that mid-session.
  Future<FakeAuthRepository> boot(WidgetTester tester, {bool signedIn = false}) async {
    final repository = FakeAuthRepository(
      sessionStorage: _InMemorySessionStorage(signedIn ? {'auth_session_email': _email} : null),
    );
    if (signedIn) await repository.restoreSession();
    addTearDown(repository.close);

    await pumpApp(tester, repository);
    return repository;
  }

  /// The router, reached through whatever page is on screen. Taken fresh each
  /// time: a redirect replaces the tree it was read from.
  GoRouter routerOf(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  Future<void> goTo(WidgetTester tester, String location) async {
    routerOf(tester).go(location);
    await tester.pumpAndSettle();
  }

  String locationOf(WidgetTester tester) =>
      routerOf(tester).routerDelegate.currentConfiguration.uri.toString();

  group('while auth is still unknown', () {
    testWidgets('nothing is redirected, so a cold boot shows no wrong screen', (tester) async {
      final repository = _PendingAuthRepository();
      addTearDown(repository.close);

      await pumpApp(tester, repository);

      // Not a redirect to landing -- landing is simply where the app starts.
      // The point is that it was left alone rather than bounced anywhere.
      expect(find.byType(LandingPage), findsOneWidget);
      expect(locationOf(tester), Routes.landing);
    });

    testWidgets('a protected route is not thrown away before auth is known', (tester) async {
      // The lock-out case: redirecting on `unknown` would boot every deep link
      // back to landing on cold start, before the session had a chance to load.
      final repository = _PendingAuthRepository();
      addTearDown(repository.close);
      await pumpApp(tester, repository);

      await goTo(tester, Routes.home);

      expect(locationOf(tester), Routes.home);
    });
  });

  group('signed out', () {
    testWidgets('a protected route sends you to the landing screen', (tester) async {
      await boot(tester);

      await goTo(tester, Routes.home);

      expect(find.byType(LandingPage), findsOneWidget);
      expect(locationOf(tester), Routes.landing);
    });

    testWidgets('the player redirects too, though it sits outside the shell', (tester) async {
      await boot(tester);

      await goTo(tester, Routes.player);

      expect(find.byType(LandingPage), findsOneWidget);
    });

    testWidgets('a detail deep link inside a tab redirects', (tester) async {
      await boot(tester);

      await goTo(tester, Routes.detailUnder(Routes.home, 'dm1'));

      expect(find.byType(LandingPage), findsOneWidget);
    });

    testWidgets('sign up stays reachable', (tester) async {
      await boot(tester);

      await goTo(tester, Routes.signUp);

      expect(find.byType(SignUpPage), findsOneWidget);
    });

    testWidgets('log in stays reachable', (tester) async {
      await boot(tester);

      await goTo(tester, Routes.logIn);

      expect(find.byType(LogInPage), findsOneWidget);
    });
  });

  group('signing in', () {
    testWidgets('leaves the auth screens for home without anyone navigating', (tester) async {
      final repository = await boot(tester);
      await goTo(tester, Routes.logIn);

      // Not awaited, and pumped past the fake's 600ms delay by hand:
      // pumpAndSettle stops as soon as nothing is scheduled, which is long
      // before a pending timer fires.
      unawaited(repository.logIn(email: _email, password: _password));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(locationOf(tester), Routes.home);
    });
  });

  group('signed in', () {
    testWidgets('boots straight into the shell', (tester) async {
      await boot(tester, signedIn: true);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(locationOf(tester), Routes.home);
    });

    testWidgets('the auth screens bounce back to home', (tester) async {
      await boot(tester, signedIn: true);

      await goTo(tester, Routes.logIn);

      expect(find.byType(LogInPage), findsNothing);
      expect(locationOf(tester), Routes.home);
    });

    testWidgets('a protected route is left alone', (tester) async {
      await boot(tester, signedIn: true);

      await goTo(tester, Routes.library);

      expect(find.text('Your Library'), findsOneWidget);
      expect(locationOf(tester), Routes.library);
    });
  });

  group('signing out', () {
    testWidgets('returns to the landing screen from inside the app', (tester) async {
      final repository = await boot(tester, signedIn: true);

      unawaited(repository.logOut());
      await tester.pumpAndSettle();

      expect(find.byType(LandingPage), findsOneWidget);
      expect(locationOf(tester), Routes.landing);
    });
  });

  group('Routes', () {
    test('detailUnder stacks detail inside the tab it was opened from', () {
      expect(Routes.detailUnder(Routes.home, 'dm1'), '/home/detail/dm1');
      expect(Routes.detailUnder(Routes.search, 'dm1'), '/search/detail/dm1');
      expect(Routes.detailUnder(Routes.library, 'dm1'), '/library/detail/dm1');
    });
  });
}
