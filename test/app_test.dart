import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/app.dart';
import 'package:spotify_clone/auth/repository/fake_auth_repository.dart';
import 'package:spotify_clone/auth/repository/session_storage.dart';

/// A pure in-memory SessionStorage so this test never touches a real
/// platform channel.
class _InMemorySessionStorage implements SessionStorage {
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
    // Keep the test hermetic/fast: never attempt a real network font fetch.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('MyApp boots to the Landing screen with no restored session', (tester) async {
    final repository = FakeAuthRepository(sessionStorage: _InMemorySessionStorage());

    await tester.pumpWidget(MyApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Sign up free'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);

    await repository.close();
  });
}
