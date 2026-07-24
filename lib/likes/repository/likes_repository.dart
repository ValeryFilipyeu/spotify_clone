/// The set of things a *given user* has "liked" (saved), by id. Likes are
/// per-account: every method takes the owning [userId] so one device can hold
/// several users' libraries side by side without them bleeding together.
///
/// The id space is shared across catalog items (albums/playlists) and tracks --
/// their ids never collide (a track id like `ab1-1` always carries its parent's
/// prefix), so a single set per user is enough and the UI resolves each id back
/// to its kind.
///
/// This is the seam a real "saved library" backend would plug into
/// (`PUT/DELETE /me/library/{id}`); the local implementation persists to a
/// [KeyValueStore] instead, namespaced per user.
abstract class LikesRepository {
  /// The currently-liked ids for [userId], restored from storage.
  Future<Set<String>> fetchLikedIds(String userId);

  /// Adds [id] to [userId]'s liked set (no-op if already liked) and persists.
  Future<void> like(String userId, String id);

  /// Removes [id] from [userId]'s liked set (no-op if not liked) and persists.
  Future<void> unlike(String userId, String id);
}
