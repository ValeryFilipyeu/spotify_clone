/// The greeting Home leads with, chosen from the time of day -- the cheapest
/// kind of personalisation there is, and what Spotify's own home screen does.
///
/// A plain function of its argument rather than anything that reads the clock
/// itself, so it is exhaustively testable and the caller stays in charge of
/// "now". Boundaries match the everyday sense of the words: morning until noon,
/// afternoon until 18:00, evening after that (including the small hours -- at
/// 2am "Good evening" reads better than "Good morning" to somebody who has not
/// been to bed).
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 18) return 'Good afternoon';
  return 'Good evening';
}
