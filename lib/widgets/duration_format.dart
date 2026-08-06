/// Formats a track length/position as "m:ss" (e.g. 3:07). Shared by the
/// tracklist tiles and the player UIs.
String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// The same duration as words, for anything a screen reader reads aloud:
/// "3 minutes 7 seconds".
///
/// [formatDuration]'s "3:07" is fine to look at but ambiguous to hear -- a
/// screen reader is as likely to say "three oh seven" (a clock time) as
/// anything useful, and "0:12" comes out as "zero twelve". Whole minutes and
/// sub-minute durations drop the half that would be spoken as zero.
String spokenDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  final minutePart = '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  final secondPart = '$seconds ${seconds == 1 ? 'second' : 'seconds'}';

  if (minutes == 0) return secondPart;
  if (seconds == 0) return minutePart;
  return '$minutePart $secondPart';
}
