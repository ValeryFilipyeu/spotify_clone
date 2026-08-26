import '../models/liked_id.dart';

/// What a given user has saved. Per-account, so one device can hold several
/// libraries without them bleeding together.
///
/// Entries are [LikedId]s rather than bare ids: the id space is not safely
/// shared across kinds -- see [LikedId].
///
/// The seam a real saved-library backend would plug into.
abstract class LikesRepository {
  /// The currently-liked entries for [userId], restored from storage.
  Future<Set<LikedId>> fetchLikedIds(String userId);

  /// Adds [likedId] to [userId]'s set (no-op if already there) and persists.
  Future<void> like(String userId, LikedId likedId);

  /// Removes [likedId] from [userId]'s set (no-op if absent) and persists.
  Future<void> unlike(String userId, LikedId likedId);
}
