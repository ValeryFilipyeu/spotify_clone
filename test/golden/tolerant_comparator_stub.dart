/// Web stand-in for [tolerant_comparator_io.dart].
///
/// The golden tests are `@TestOn('vm')` and never run in a browser, but that
/// annotation only stops them *running*: `flutter test --platform chrome`
/// compiles every file under `test/` into one bundle first, and a compile error
/// anywhere fails the whole web run. The real comparator extends
/// `LocalFileComparator`, which on web is a different class from a different
/// library (`_goldens_web.dart`) with none of the members it overrides -- no
/// `basedir`, no `getGoldenBytes`, no `generateFailureOutput`, and a constructor
/// taking no arguments.
///
/// So the implementation lives in a VM-only file behind a conditional import,
/// and this is what the web compiler sees instead. It is never called.
void useTolerantGoldens({double maxDifferentRatio = 0}) {}
