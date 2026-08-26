import 'package:equatable/equatable.dart';

/// What kind of thing a like refers to.
enum LikeKind {
  /// An album or a playlist -- whatever [CatalogItem] covers.
  item,

  /// A single song.
  track,
}

/// One entry in a user's library: a catalog id together with what kind of thing
/// it names.
///
/// The kind is not decoration. Likes used to be a plain `Set<String>` of ids, on
/// the stated assumption that "a track id always carries its parent's prefix, so
/// they never collide". That was true of the hardcoded catalog the app started
/// with and is false of the real one: Audius encodes track ids and playlist ids
/// from the same alphabet, and they do collide. Measured on a live account --
/// `aA8xa` is at once the playlist *LATIN ELECTRONIC MUSIC* and the song *Reflxt
/// Ride Nb. 08*. One like, and Your Library listed both: an album the user saved
/// and a song they had never heard of, with its heart already filled in.
///
/// So an id alone cannot answer "is this liked?", and neither can the catalog --
/// asking it resolves the id, but the question is about what the *user* pressed.
/// The kind has to be recorded at the moment of pressing, which is the one moment
/// it is known for certain: every heart in the app sits next to either an item or
/// a track, never something that could be either.
class LikedId extends Equatable {
  const LikedId(this.kind, this.id);

  const LikedId.item(String id) : this(LikeKind.item, id);
  const LikedId.track(String id) : this(LikeKind.track, id);

  final LikeKind kind;
  final String id;

  /// The stored form, `<kind>:<id>`.
  ///
  /// The kind goes first so the shape is unambiguous however odd the id is: ids
  /// from a hashid scheme have no colons today, but nothing promises that, and
  /// splitting on the *first* colon means one that does still round-trips.
  String encode() => '${kind.name}:$id';

  /// [encode]'s inverse, or null for anything that is not one of ours.
  ///
  /// Null is also what every id written by the untyped version decodes to, and
  /// that is the whole migration: they are dropped on the next read. Guessing a
  /// kind for them was the alternative, and guessing wrong is exactly the bug
  /// above -- a stranger's song sitting in someone's library. Nothing here has
  /// ever shipped, so the cost is a handful of hearts on a demo account, paid
  /// once.
  static LikedId? tryParse(String encoded) {
    final separator = encoded.indexOf(':');
    if (separator <= 0 || separator == encoded.length - 1) return null;

    final name = encoded.substring(0, separator);
    final kind = LikeKind.values.where((k) => k.name == name).firstOrNull;
    return kind == null ? null : LikedId(kind, encoded.substring(separator + 1));
  }

  @override
  List<Object?> get props => [kind, id];

  @override
  String toString() => encode();
}
