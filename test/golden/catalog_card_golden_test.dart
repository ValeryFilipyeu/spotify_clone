@TestOn('vm')
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/models/catalog_item.dart';
import 'package:spotify_clone/home/widgets/catalog_card.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';

import 'golden_harness.dart';

const _item = CatalogItem(
  id: 'dm1',
  title: 'Daily Mix 1',
  subtitle: 'Tame Impala, MGMT & more',
  coverColor: 0xFF1DB954,
);

/// Long enough that both lines have to give up, which is the state a card is
/// most likely to be wrong in and the one no fixture in the app produces.
const _overflowing = CatalogItem(
  id: 'long',
  title: 'Ultra Deluxe Extended Anniversary Remaster Edition',
  subtitle: 'Featuring absolutely everybody who has ever recorded anything, plus guests',
  coverColor: 0xFF2D46B9,
);

class _NoLikes implements LikesRepository {
  @override
  Future<Set<String>> fetchLikedIds(String userId) async => const {};

  @override
  Future<void> like(String userId, String id) async {}

  @override
  Future<void> unlike(String userId, String id) async {}
}

Widget _card(WidgetTester tester, CatalogItem item) {
  final cubit = LikesCubit(
    repository: _NoLikes(),
    authStateChanges: Stream.value(const AppUser('u@spotify.com')),
  );
  addTearDown(cubit.close);

  return BlocProvider.value(
    value: cubit,
    child: CatalogCard(item: item, onTap: () {}),
  );
}

/// The card is the densest piece of layout in the app -- a cover, two clipped
/// text lines, and a heart sitting on a disc over the artwork -- and it has
/// already had a bug in exactly that stack. From the widget's own notes, the
/// heart and its disc were once two `Positioned`s pinned to the same corner,
/// which drew the heart 4px up and right of the disc whenever the IconButton
/// was not exactly 48x48.
///
/// That is the class of bug a golden exists for: invisible to a finder-based
/// test (both widgets present, both tappable, semantics unchanged) and obvious
/// in a picture.
///
/// A note on what is NOT here, because it was tried and removed. The obvious
/// companion test is "renders identically at desktop density", on the theory
/// that a desktop's compact density shrinks the IconButton and moves the heart
/// again. It cannot: the heart and disc are now centred inside a fixed 48x48
/// box, so the button's own size no longer positions anything. That was
/// confirmed by sabotage -- removing the fixed box, and separately removing the
/// theme's `materialTapTargetSize` pin, both left the two platforms rendering
/// byte-identical output. A test that cannot fail is worse than no test, so
/// there is one golden of this card and not two.
void main() {
  setUpAll(setUpGoldens);

  group('CatalogCard', () {
    testWidgets('at mobile density', (tester) async {
      await expectGolden(
        tester,
        'catalog_card',
        size: const GoldenSize(190, 230),
        child: _card(tester, _item),
      );
    });

    testWidgets('clips a title and subtitle too long to fit', (tester) async {
      // The card is a fixed 150 wide, so what happens past that edge is a
      // decision the layout makes rather than one anybody wrote down: one line
      // ellipsized, two lines then ellipsized. A golden is the cheapest way to
      // notice if a style change quietly turns that into three lines and pushes
      // the row's height out.
      await expectGolden(
        tester,
        'catalog_card_overflowing_text',
        size: const GoldenSize(190, 230),
        child: _card(tester, _overflowing),
      );
    });
  });
}
