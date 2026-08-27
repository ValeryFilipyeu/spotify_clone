import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/landing/view/landing_page.dart';
import 'package:spotify_clone/router/app_routes.dart';

/// Just enough router for the two buttons to have somewhere to go.
GoRouter _router() => GoRouter(
  initialLocation: Routes.landing,
  routes: [
    GoRoute(path: Routes.landing, builder: (context, state) => const LandingPage()),
    GoRoute(
      path: Routes.signUp,
      builder: (context, state) => const Scaffold(body: Text('up')),
    ),
    GoRoute(
      path: Routes.logIn,
      builder: (context, state) => const Scaffold(body: Text('in')),
    ),
  ],
);

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Every viewport here is wide on purpose. `flutter test` draws each glyph as a
  // filled box, so the wordmark measures ~464dp instead of the ~258dp a real
  // font gives it, and a phone-width surface would fail on that rather than on
  // anything this file is about. See golden_harness.dart. Height is the axis
  // under test.

  testWidgets('lays out with room to spare', (tester) async {
    await pumpAt(tester, const Size(800, 844));

    expect(find.text('Sign up free'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  // The reported case: a short browser window left the content ~52dp taller
  // than the space it was given, and a RenderFlex overflow is a test failure.
  testWidgets('does not overflow a short viewport', (tester) async {
    await pumpAt(tester, const Size(800, 260));

    expect(find.text('Sign up free'), findsOneWidget);
  });

  testWidgets('scrolls to the buttons when it cannot fit them', (tester) async {
    await pumpAt(tester, const Size(800, 200));

    await tester.scrollUntilVisible(find.text('Log in'), 60);

    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('still centres its content when there is room to spare', (tester) async {
    await pumpAt(tester, const Size(800, 900));

    // The Spacers only do anything if the column was stretched to the viewport;
    // without that the wordmark would sit at the top under the padding.
    final wordmark = tester.getCenter(find.text('spotify clone'));
    expect(wordmark.dy, greaterThan(200));
  });
}
