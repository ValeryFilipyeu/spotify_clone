import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compares goldens exactly, and reports by how much when they differ.
///
/// Exact by default, from two measurements. A real regression is *small* --
/// taking [CoverArt]'s corner radius from 8 to 6 moves 0.15%-0.22% of pixels --
/// while the same code on macOS and Linux differs by 0.46%-3.95%. Drift is an
/// order of magnitude larger than signal, so no threshold separates them: an
/// early draft allowed 0.5% and silently passed the corner-radius sabotage.
///
/// So a golden belongs to the platform that wrote it, and these are macOS-only.
/// [maxDifferentRatio] stays a knob for a future case with evidence behind it.
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
