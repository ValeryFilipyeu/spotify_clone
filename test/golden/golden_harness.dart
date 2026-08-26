import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/theme/spotify_theme.dart';

// VM-only: the real comparator extends a `LocalFileComparator` that does not
// exist in the web build of flutter_test. See tolerant_comparator_stub.dart.
import 'tolerant_comparator_stub.dart' if (dart.library.io) 'tolerant_comparator_io.dart';

/// Shared setup for the golden tests: a fixed surface, a fixed platform, and an
/// exact comparator that reports how far off it was when it fails.
///
/// **What these test is layout, not typography.** `flutter test` draws every
/// glyph as a filled box, so a golden records where blocks sit and where they
/// wrap -- a title that stops fitting, a control pushed off an edge. What is
/// *announced* is the semantics tests' job.
///
/// **Three things are pinned** so a golden means the same on another machine:
/// the target platform (`defaultTargetPlatform` is the host, and ThemeData reads
/// density and tap-target size off it), the surface (the 800x600 default at 3x
/// bakes a 2400x1800 PNG for one small widget), and the device pixel ratio.
///
/// **They are macOS-only** because none of that fixes how a machine rasterizes
/// an edge. The same code renders 0.46%-3.95% differently on Linux -- every
/// glyph and rectangle *outline* -- where a real regression measures 0.15%.
/// Drift exceeds signal, so no tolerance can separate them; the Linux job skips
/// them by the `golden` tag. See [useTolerantGoldens].

/// A golden's surface, in logical pixels. Small on purpose: a diff of a whole
/// screen says something changed without saying what.
class GoldenSize {
  const GoldenSize(this.width, this.height);

  final double width;
  final double height;

  Size get size => Size(width, height);
}

/// The app's own theme, built as though on one fixed platform.
///
/// Pinned rather than parameterised. `ThemeData` resolves platform-derived
/// defaults -- `visualDensity`, `materialTapTargetSize`, page transitions,
/// scrollbars -- at *construction*, from `defaultTargetPlatform`, which in a
/// test is whichever machine is running it. Left alone, a golden would record
/// the developer's Mac and be compared against a Linux runner's idea of the
/// same widget.
///
/// The override has to be in place while the theme is being built. Applying
/// `copyWith(platform:)` afterwards looks equivalent and is not: the defaults
/// are already baked in by then, so the golden would still record the host.
///
/// Android, because it is the one platform whose defaults are not conditional
/// on anything else -- and because the choice only has to be *fixed*, not
/// correct. A golden records a layout, and this makes sure it is the same
/// layout everywhere.
ThemeData goldenTheme({TargetPlatform platform = TargetPlatform.android}) {
  debugDefaultTargetPlatformOverride = platform;
  final theme = SpotifyTheme.dark();
  // Dropped immediately: the density is now part of `theme`, and flutter_test
  // fails any test that ends with this still set.
  debugDefaultTargetPlatformOverride = null;
  return theme;
}

/// Renders [child] at [size] and compares it against `goldens/<name>.png`.
///
/// Regenerate with:
///
/// ```
/// fvm flutter test test/golden --update-goldens
/// ```
///
/// [pumpFor] pins the frame for anything that animates forever.
/// `pumpAndSettle` cannot be used on those -- it pumps until no frame is
/// scheduled, and a repeating ticker always has one, so it runs to its timeout
/// and fails. Giving an elapsed time instead picks one exact frame out of the
/// loop, which is reproducible precisely because the animation is a pure
/// function of how long it has been running.
Future<void> expectGolden(
  WidgetTester tester,
  String name, {
  required GoldenSize size,
  required Widget child,
  Duration? pumpFor,
  Future<void> Function()? afterPump,
}) async {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size.size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: goldenTheme(),
      // Otherwise every golden carries a red diagonal ribbon across one corner,
      // which is both noise and a moving target if the banner ever restyles.
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  // Settle the tree first, then let the caller drive it into the state being
  // photographed. Some state cannot be passed in as a constructor argument --
  // a bloc fed by streams reaches it by being *told*, and only once it is live
  // and listening. Emitting before the first pump races the bloc's own startup
  // and is silently dropped.
  await tester.pump();
  if (afterPump != null) {
    await afterPump();
    await tester.pump();
  }

  if (pumpFor == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(pumpFor);
  }

  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

/// Call once per golden test file, from `setUpAll`.
void setUpGoldens() {
  // The runtime fetch would be a network call from a test, and google_fonts
  // throws rather than doing it. The bundled fallback is what renders.
  GoogleFonts.config.allowRuntimeFetching = false;
  useTolerantGoldens();
}
