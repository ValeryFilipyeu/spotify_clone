/// Formats a track length/position as "m:ss" (e.g. 3:07). Shared by the
/// tracklist tiles and the player UIs.
String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
