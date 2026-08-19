import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compares goldens exactly, and reports by how much when they differ.
///
/// The default [maxDifferentRatio] is zero -- exact -- and that is a decision
/// with two measurements behind it rather than a default nobody chose.
///
/// The tempting move is to allow a small percentage, so that antialiasing
/// computed by whatever CPU is running cannot fail a build. Two numbers say why
/// that cannot work here:
///
///  * A change anyone would call a regression is *small*. Taking [CoverArt]'s
///    corner radius from 8 to 6 moves only **0.15% to 0.22%** of the pixels in
///    these images, because it only touches pixels along a curve.
///  * The same code rendered on macOS and on Linux differs by **0.46% to
///    3.95%**, with single channels off by as much as 179 of 255. Measured by
///    taking the images CI uploaded and diffing them against the committed
///    goldens.
///
/// Cross-platform drift is therefore an order of magnitude *larger* than a real
/// regression, and no threshold can separate the two. An early draft allowed
/// 0.5% and silently passed the corner-radius sabotage.
///
/// The conclusion is not a bigger allowance, it is that a golden belongs to the
/// platform that wrote it -- which is why these are generated and verified on
/// macOS only, and skipped on the Linux job. [maxDifferentRatio] stays as a knob
/// for a future case with evidence behind it, and defaults to demanding an exact
/// match.
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
      // Under the ceiling: reported rather than passed in silence, so a steady
      // climb towards the limit is visible before it starts failing.
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
