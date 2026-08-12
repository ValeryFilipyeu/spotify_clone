import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/models/catalog_item.dart';
import 'package:spotify_clone/home/widgets/catalog_card.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';
import 'package:spotify_clone/likes/widgets/like_button.dart';
import 'package:spotify_clone/theme/spotify_theme.dart';

const _item = CatalogItem(
  id: 'dm1',
  title: 'Daily Mix 1',
  subtitle: 'Tame Impala, MGMT & more',
  coverColor: 0xFF1DB954,
);

class _NoLikes implements LikesRepository {
  @override
  Future<Set<String>> fetchLikedIds(String userId) async => const {};

  @override
  Future<void> like(String userId, String id) async {}

  @override
  Future<void> unlike(String userId, String id) async {}
}

/// Pumps a card under the app's own theme, built as it would be on [platform].
///
/// Which platform matters more than it looks: [ThemeData] defaults visualDensity
/// to `VisualDensity.defaultDensityForPlatform`, which is `compact` on every
/// desktop -- and web reports the HOST platform, so a browser on a Mac gets the
/// desktop density too. Compact trims 8dp off every button in both axes.
///
/// The override has to be in place while the theme is *constructed*, which is
/// the only moment that default is resolved. `SpotifyTheme.dark().copyWith(
/// platform: macOS)` looks like it would do the same thing and does not: the
/// density is already baked in by then, so the test would pass no matter what
/// the theme said. (It did, until this was caught.)
Future<void> pumpCard(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  final theme = SpotifyTheme.dark();
  // Safe to drop straight away: whatever density applies is now part of `theme`,
  // and flutter_test fails any test that ends with this still set.
  debugDefaultTargetPlatformOverride = null;

  final cubit = LikesCubit(
    repository: _NoLikes(),
    authStateChanges: Stream.value(const AppUser('u@spotify.com')),
  );
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: Center(
            child: CatalogCard(item: _item, onTap: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    group('on ${platform.name}', () {
      testWidgets('the heart sits dead centre of its scrim disc', (tester) async {
        await pumpCard(tester, platform);

        // The scrim is a plain sibling sized to the tap target, so if the two
        // stop agreeing on that size the heart drifts out of its disc.
        final scrim = tester.getRect(
          find.descendant(of: find.byType(CatalogCard), matching: find.byType(IgnorePointer)),
        );
        final heart = tester.getRect(find.byType(LikeButton));

        expect(heart.center, scrim.center);
      });

      testWidgets('the heart keeps a legal tap target', (tester) async {
        await pumpCard(tester, platform);

        // 48dp Android, 44pt iOS. A desktop theme quietly trims IconButton to
        // 40x40, which is under both.
        final heart = tester.getSize(find.byType(LikeButton));
        expect(heart.width, greaterThanOrEqualTo(48));
        expect(heart.height, greaterThanOrEqualTo(48));
      });
    });
  }
}
