/// Per-account "recently played": items playback was started from, newest first.
///
/// Ids only. Resolving them is the catalog's job, so history never goes stale
/// when the catalog changes.
abstract class PlayHistoryRepository {
  /// One home row's worth; an unbounded list would grow for ever on disk.
  static const int maxEntries = 8;

  /// [userId]'s history, most recent first. Empty for an account that has never
  /// played anything.
  Future<List<String>> fetchRecentIds(String userId);

  /// Moves [itemId] to the front of [userId]'s history (see [withMostRecent]).
  Future<void> record(String userId, String itemId);
}

/// [ids] with [itemId] moved to the front, capped at
/// [PlayHistoryRepository.maxEntries].
///
/// Shared by the repository and the cubit on purpose: the cubit applies it
/// optimistically, and two implementations would let the screen and the disk
/// drift apart. Remove-then-prepend, so a replay moves an entry rather than
/// adding a second copy.
List<String> withMostRecent(List<String> ids, String itemId) =>
    [itemId, ...ids.where((id) => id != itemId)].take(PlayHistoryRepository.maxEntries).toList();
