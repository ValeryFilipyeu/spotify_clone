import '../models/liked_id.dart';

/// The set of things a *given user* has "liked" (saved). Likes are per-account:
/// every method takes the owning [userId] so one device can hold several users'
/// libraries side by side without them bleeding together.
///
/// Entries are [LikedId]s rather than bare ids, because the id space is *not*
/// shared safely across kinds -- see [LikedId] for the collision that says so.
///
/// This is the seam a real "saved library" backend would plug into
/// (`PUT/DELETE /me/library/{id}`); the local implementation persists to a
/// [KeyValueStore] instead, namespaced per user.
abstract class LikesRepository {
  /// The currently-liked entries for [userId], restored from storage.
  Future<Set<LikedId>> fetchLikedIds(String userId);

  /// Adds [likedId] to [userId]'s set (no-op if already there) and persists.
  Future<void> like(String userId, LikedId likedId);

  /// Removes [likedId] from [userId]'s set (no-op if absent) and persists.
  Future<void> unlike(String userId, LikedId likedId);
}
