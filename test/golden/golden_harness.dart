import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/theme/spotify_theme.dart';

/// Shared setup for the golden tests: a fixed surface, a fixed platform, and an
/// exact comparator that reports how far off it was when it fails.
///
/// ## What a golden here is actually testing
///
/// Not typography. `flutter test` renders every glyph as a filled box -- there
/// is no real font in the test environment, and none is loaded -- so a golden
/// records where the *blocks* sit, how wide they are, and where they wrap or
/// overflow. That is a feature rather than a limitation: font rasterization is
/// the single largest source of golden churn between machines, and removing it
/// leaves behind exactly the thing worth pinning, which is layout.
///
/// It also means these goldens say nothing about whether a label reads well.
/// The semantics tests cover what is announced; these cover where it is.
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
/// The one difference left unpinned is the antialiasing of curves, computed by
/// whatever CPU is running. Comparison is exact anyway, for a reason worth
/// reading before loosening it -- see [useTolerantGoldens].

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

/// Compares goldens exactly, and reports by how much when they differ.
///
/// The default [maxDifferentRatio] is zero -- exact -- and that is a decision
/// with a measurement behind it rather than a default nobody chose.
///
/// The tempting move is to allow a small percentage, on the grounds that
/// antialiasing along a curve is computed by whatever CPU is running and might
/// disagree in the last bit between a developer's Mac and a Linux runner. The
/// problem is scale. Changing [CoverArt]'s corner radius from 8 to 6 -- a change
/// anyone would call visible, and a regression worth failing a build over --
/// moves only **0.15% to 0.22%** of the pixels in these images, because it too
/// only touches pixels along a curve. Measured, by making that exact change and
/// reading the numbers below.
///
/// So a tolerance generous enough to absorb cross-platform antialiasing is, on
/// this evidence, also generous enough to absorb real regressions: an early
/// draft of this file allowed 0.5% and silently passed that sabotage. There is
/// no safe number to guess at, and guessing wrong fails silently in the
/// direction that matters.
///
/// Exact, therefore, until a real cross-platform failure provides the figure to
/// set instead -- and if that figure is anywhere near 0.15%, the honest
/// conclusion is that these goldens have to be generated on the platform that
/// verifies them, not that the allowance should be raised to fit.
void useTolerantGoldens({double maxDifferentRatio = 0}) {
  final existing = goldenFileComparator as LocalFileComparator;
  goldenFileComparator = _TolerantGoldenComparator(existing.basedir, maxDifferentRatio);
}

class _TolerantGoldenComparator extends LocalFileComparator {
  /// [LocalFileComparator] wants the *test file* and keeps its directory, so
  /// the basedir is handed back to it as a file inside itself.
  _TolerantGoldenComparator(Uri basedir, this._maxDifferentRatio)
    : super(basedir.resolve('golden_test.dart'));

  final double _maxDifferentRatio;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed) {
      result.dispose();
      return true;
    }

    if (result.diffPercent <= _maxDifferentRatio) {
      // Under the ceiling: report it rather than passing in silence, so a
      // steady climb towards the limit is visible before it starts failing.
      debugPrint(
        'Golden ${golden.pathSegments.last} differs by '
        '${(result.diffPercent * 100).toStringAsFixed(4)}% of pixels, '
        'within the ${(_maxDifferentRatio * 100).toStringAsFixed(2)}% allowance.',
      );
      result.dispose();
      return true;
    }

    final failure = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(failure);
  }
}
