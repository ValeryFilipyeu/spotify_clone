/// The tint painted *beneath* a cover, for catalog data that carries none.
///
/// Derived from the item's id rather than picked at random: a gradient that
/// changed between two visits to the same playlist would read as a bug. The
/// palette is the set the hardcoded catalog used.
abstract final class CoverPalette {
  /// Dark enough that white text over the gradient stays legible.
  static const List<int> colors = [
    0xFF1DB954, // green
    0xFFE13300, // vermilion
    0xFF7358FF, // violet
    0xFF2D46B9, // indigo
    0xFFBA5D07, // amber
    0xFF503750, // plum
    0xFF8D67AB, // lilac
    0xFF477D95, // teal
    0xFFE8115B, // magenta
    0xFF148A08, // forest
    0xFFDC148C, // pink
    0xFF056952, // pine
  ];

  /// The tint for [seed], stable across runs, platforms and releases.
  static int forSeed(String seed) => colors[_hash(seed) % colors.length];

  /// Not `seed.hashCode`, which is only promised to be stable within one run --
  /// it may differ between the VM and the web compilers, so a playlist would be
  /// green on Android and magenta in the browser.
  ///
  /// The mask keeps every intermediate value well under 2^53, which is the real
  /// constraint here: on the web Dart's `int` is a JavaScript double, so
  /// arithmetic above that silently loses precision -- and a hash that loses its
  /// low bits on one platform only is exactly the kind of divergence this
  /// function exists to avoid. A classic FNV-1a would overflow it on the first
  /// multiply.
  static int _hash(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x1FFFFFFF;
    }
    return hash;
  }
}
