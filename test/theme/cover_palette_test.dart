import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/theme/cover_palette.dart';

/// The same hash, defined in arbitrary precision.
///
/// Pinning the implementation against an exact definition catches two different
/// regressions: changing the algorithm, and losing precision while keeping it.
/// The second is the one worth explaining. On the web Dart's `int` is a
/// JavaScript double, so any intermediate value above 2^53 silently drops its
/// low bits -- and a lossy hash is perfectly self-consistent, so "same seed,
/// same colour" cannot detect it.
///
/// Note precision loss only *bites* under `flutter test --platform chrome`;
/// on the VM ints are 64-bit and the arithmetic is exact either way. Measured
/// with the textbook FNV-1a this deliberately does not use: computed in `int`
/// and in `BigInt` it agrees on the VM and disagrees on chrome (1003383502 vs
/// 2266066580 for seed 'RKxOQ'). Hence the mask in [CoverPalette], and hence
/// this file being worth running on both platforms.
int referenceHash(String seed) {
  var hash = BigInt.zero;
  for (final unit in seed.codeUnits) {
    hash = (hash * BigInt.from(31) + BigInt.from(unit)) & BigInt.from(0x1FFFFFFF);
  }
  return hash.toInt();
}

void main() {
  test('a seed always gets the same colour', () {
    // A cover that changed tint between two visits to the same playlist would
    // read as a rendering bug.
    expect(CoverPalette.forSeed('RKxOQ'), CoverPalette.forSeed('RKxOQ'));
  });

  test('every colour comes from the palette', () {
    for (final seed in ['RKxOQ', 'ebd1O', '95wro', 'ng9rl', '8ME7P', 'NvO7jZY', '']) {
      expect(CoverPalette.colors, contains(CoverPalette.forSeed(seed)));
    }
  });

  test('the palette is actually spread across seeds', () {
    // A hash that collapsed everything onto one colour would satisfy every
    // other test in this file.
    final seeds = [for (var i = 0; i < 200; i++) 'playlist-$i'];
    final used = {for (final seed in seeds) CoverPalette.forSeed(seed)};

    expect(used.length, CoverPalette.colors.length);
  });

  test('the arithmetic stays exact, including where a JS double would not', () {
    final seeds = [
      'RKxOQ',
      'a',
      '',
      'a-very-long-identifier-of-the-kind-a-hash-based-id-scheme-produces',
      'x' * 500,
      '학습 lofi hiphop mix', // multi-byte, since the hash walks UTF-16 code units
    ];

    for (final seed in seeds) {
      expect(
        CoverPalette.forSeed(seed),
        CoverPalette.colors[referenceHash(seed) % CoverPalette.colors.length],
        reason: 'precision loss on seed of length ${seed.length}',
      );
    }
  });

  test('every colour is fully opaque', () {
    // The tint is painted as the bottom layer of a gradient, so a translucent
    // one would let the scaffold show through and wash the cover out.
    for (final color in CoverPalette.colors) {
      expect(color >> 24 & 0xFF, 0xFF);
    }
  });
}
