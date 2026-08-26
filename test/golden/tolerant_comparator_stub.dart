/// Web stand-in for [tolerant_comparator_io.dart]. Never called.
///
/// `@TestOn('vm')` stops the golden tests *running* in a browser, but
/// `--platform chrome` still compiles every file under `test/` into one bundle,
/// and web's `LocalFileComparator` is a different class with none of the members
/// the real comparator overrides.
void useTolerantGoldens({double maxDifferentRatio = 0}) {}
