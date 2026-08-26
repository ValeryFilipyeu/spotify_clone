import '../../../network/json_reader.dart';

/// Reads an Audius `artwork` object into an ordered list of places the same
/// image can be fetched from.
///
/// The sized keys are full urls on whichever node the API picked; `mirrors` are
/// bare origins holding the same content. Storage is content-addressed, so the
/// path is identical everywhere and re-pointing it is a string operation rather
/// than another API call.
///
/// Worth doing because nodes die individually and often: measured on eight live
/// tracks, three of thirty-two hosts answered 502, and per-node -- the dead host
/// 502'd for its own content, another node's, and a CID that does not exist.
/// Retrying the same url cannot work; asking a different node can.
///
/// Kept out of the domain and out of [CoverArt]: that a cover has several sources
/// is worth them knowing, how Audius spells them is not.
class AudiusArtwork {
  const AudiusArtwork._();

  /// 480 rather than 1000: the biggest cover drawn is the full player's, which
  /// even at 3x needs no more, and [CoverArt] decodes down anyway.
  static const String preferredSize = '480x480';

  /// Every url worth trying, best first: the node the API named, then the same
  /// path on each mirror. Nothing is probed for liveness -- that is a request per
  /// candidate for an answer that is stale by the time the image loads.
  static List<String> urlsFrom(Map<String, Object?>? artwork) {
    if (artwork == null) return const [];

    // Older uploads carry only some sizes, and a small cover beats a placeholder.
    final primary =
        artwork.stringOrNull(preferredSize) ??
        artwork.stringOrNull('1000x1000') ??
        artwork.stringOrNull('150x150');
    if (primary == null) return const [];

    final primaryUri = Uri.tryParse(primary);
    // No path to graft, but handing it back is no worse than having no mirrors.
    if (primaryUri == null || primaryUri.path.isEmpty) return [primary];

    // A Set, so a mirror repeating the primary host is not retried as if it were
    // a different node. Insertion-ordered, which keeps "best first" true.
    final candidates = {primary};
    for (final mirror in _mirrorsIn(artwork)) {
      final origin = Uri.tryParse(mirror);
      // Without an authority a mirror resolves to a relative uri fetching
      // nothing.
      if (origin == null || !origin.hasAuthority) continue;
      candidates.add(
        origin
            .replace(path: primaryUri.path, query: primaryUri.hasQuery ? primaryUri.query : null)
            .toString(),
      );
    }
    return candidates.toList(growable: false);
  }

  /// The `mirrors` array, skipping non-strings. Lenient where the rest of the
  /// parsing is strict: artwork is decoration, and one junk entry should not turn
  /// into a screen that will not load.
  static List<String> _mirrorsIn(Map<String, Object?> artwork) {
    final value = artwork['mirrors'];
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty) entry,
    ];
  }
}
