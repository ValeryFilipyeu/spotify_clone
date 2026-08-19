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
/// ## What a golden here is actually testing
///
/// Not typography. `flutter test` renders every glyph as a filled box -- there
/// is no real font in the test environment, and none is loaded -- so a golden
/// records where the *blocks* sit, how wide they are, and where they wrap or
/// overflow. Which is the useful part: a title that stops fitting, a subtitle
/// that grows a third line, a control pushed off an edge.
///
/// It also means these say nothing about whether a label reads well. The
/// semantics tests cover what is announced; these cover where it is.
///
/// Worth being precise about, because the obvious inference from it is wrong.
/// Boxes instead of letterforms does remove *typography* variance -- no hinting,
/// no subpixel positioning of curves -- but the boxes are still drawn by the
/// text engine, and their edges are exactly where two machines disagree. In the
/// Linux/macOS comparison below, the difference in `cover_art_placeholder` was
/// the outline of the icon glyph and nothing else: the gradient filling the
/// whole square, and the rounded corners, were byte-identical. The three
/// equalizer goldens, which contain no text at all, passed on Linux unchanged.
/// Gradients and shape antialiasing travel; glyph edges do not.
///
/// ## Why they can be trusted on a machine that did not write them
///
/// Three things are pinned, and each one is a difference that has bitten real
/// projects:
///
///  * **The target platform.** In a test `defaultTargetPlatform` is the HOST --
///    macOS on the developer's machine, Linux on the CI runner. `ThemeData`
///    resolves density, tap-target size and transitions from it at construction
///    time, so the same widget can genuinely differ between the two.
///    [goldenTheme] pins it.
///  * **The surface.** The default is 800x600 at 3x, so one small widget bakes
///    a 2400x1800 PNG. Each golden asks for the size it needs.
///  * **The device pixel ratio.** Fixed at 1, so a golden is not silently three
///    times larger in the repository than the layout it describes.
///
/// ## Why they are macOS-only
///
/// What none of that pinning can fix is how the machine rasterizes an edge.
/// Diffing the images CI rendered on Linux against these, the same code differs
/// by 0.46% to 3.95% of pixels -- every glyph and rectangle *outline*, with
/// channels off by up to 179 of 255 -- while a real regression measures 0.15%.
/// Drift is larger than signal, so no tolerance can tell them apart and a
/// golden belongs to the platform that wrote it. These are generated on macOS,
/// verified on macOS in CI, and excluded from the Linux job by the `golden` tag.
/// See [useTolerantGoldens] for the numbers.

/// A golden's surface, in logical pixels.
///
/// Small on purpose. A golden is read by a human during review, and a diff of
/// a whole 800x600 screen tells you something changed without telling you what.
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
