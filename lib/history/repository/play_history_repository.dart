/// Per-account "recently played" list: the catalog items (albums, playlists) a
/// user has started playback from, most recent first.
///
/// The seam a real backend would plug into later, exactly like
/// [LikesRepository]. Ids only -- resolving them back to catalog items is the
/// catalog's job, so history never goes stale when the catalog changes.
abstract class PlayHistoryRepository {
  /// How many entries are kept. One home row's worth: older ones are of no use
  /// to anybody and an unbounded list would grow forever in local storage.
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
/// Shared by the repository and the cubit deliberately: the cubit applies the
/// change optimistically so the UI moves at once, and if the two computed the
/// list differently, what the screen showed and what got persisted would drift
/// apart. Replaying an item you played an hour ago should move it, not add a
/// second copy -- hence remove-then-prepend rather than a plain insert.
List<String> withMostRecent(List<String> ids, String itemId) => [
      itemId,
      ...ids.where((id) => id != itemId),
    ].take(PlayHistoryRepository.maxEntries).toList();
