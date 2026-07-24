import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';
import 'package:spotify_clone/likes/widgets/like_button.dart';

class _FakeLikesRepository implements LikesRepository {
  final Map<String, Set<String>> _byUser = {};

  Set<String> _for(String userId) => _byUser.putIfAbsent(userId, () => <String>{});

  @override
  Future<Set<String>> fetchLikedIds(String userId) async => {..._for(userId)};

  @override
  Future<void> like(String userId, String id) async => _for(userId).add(id);

  @override
  Future<void> unlike(String userId, String id) async => _for(userId).remove(id);
}

void main() {
  testWidgets('tapping the heart toggles between outline and filled', (tester) async {
    final cubit = LikesCubit(
      repository: _FakeLikesRepository(),
      authStateChanges: Stream.value(const AppUser('u@spotify.com')),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: const LikeButton(id: 'ab1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // let the sign-in load settle

    // Starts unliked.
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);

    // Tap -> liked.
    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(cubit.isLiked('ab1'), isTrue);

    // Tap again -> back to unliked.
    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(cubit.isLiked('ab1'), isFalse);
  });
}
