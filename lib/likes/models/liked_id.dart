import 'package:equatable/equatable.dart';

/// What kind of thing a like refers to.
enum LikeKind {
  /// An album or a playlist -- whatever [CatalogItem] covers.
  item,

  /// A single song.
  track,
}

/// A catalog id together with what kind of thing it names.
///
/// The kind is load-bearing. Audius draws track and playlist ids from the same
/// alphabet and they do collide: `aA8xa` is at once the playlist *LATIN
/// ELECTRONIC MUSIC* and the song *Reflxt Ride Nb. 08*. When likes were bare ids,
/// saving the playlist put the song in the user's library too.
///
/// The catalog cannot settle it either -- it resolves an id, but the question is
/// what the *user* pressed. So the kind is recorded at the press, which is the
/// one moment it is certain.
class LikedId extends Equatable {
  const LikedId(this.kind, this.id);

  const LikedId.item(String id) : this(LikeKind.item, id);
  const LikedId.track(String id) : this(LikeKind.track, id);

  final LikeKind kind;
  final String id;

  /// The stored form, `<kind>:<id>`. Kind first, so an id that one day contains
  /// a colon still round-trips.
  String encode() => '${kind.name}:$id';

  /// [encode]'s inverse, or null for anything else -- including every id the
  /// untyped version wrote, which is the whole migration. Guessing a kind for
  /// those is exactly the bug above.
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
