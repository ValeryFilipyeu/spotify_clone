import '../../../network/json_reader.dart';

/// Reads an Audius `artwork` object into an ordered list of places the same
/// image can be fetched from.
///
/// Audius stores content on a peer-to-peer network of independently operated
/// nodes, and says so in the payload:
///
/// ```json
/// "artwork": {
///   "480x480": "https://validator.stuffisup.com/content/QmRDas.../480x480.jpg",
///   "mirrors": ["https://val005.open-audio-validator.com",
///               "https://v.monophonic.digital",
///               "https://audius-discovery-1.altego.net"]
/// }
/// ```
///
/// The sized keys are full urls on whichever node the API picked; `mirrors` are
/// bare origins for nodes holding the same content. Storage is content-addressed
/// -- the `Qm...` segment is a hash of the bytes -- so the path after the origin
/// is identical everywhere, and pointing it at a mirror is a string operation
/// rather than another API call.
///
/// This matters because those nodes go down individually and often. Measured
/// against the live API on a search for eight tracks: one track's *primary* host
/// answered 502 while all three of its mirrors served the image, and two more
/// hosts listed as mirrors elsewhere were also 502 -- three dead out of
/// thirty-two. The failure is per-node, not per-file: the dead host answered 502
/// for its own content, for another node's content, and for a CID that does not
/// exist, five times running. So retrying the url we were given cannot work, and
/// asking a different node is the only thing that can.
///
/// Kept out of the domain and out of [CoverArt] on purpose. That a cover has
/// several interchangeable sources is worth both of them knowing; that Audius
/// spells them as an origin list needing a path grafted on is not.
class AudiusArtwork {
  const AudiusArtwork._();

  /// Which of the three sizes Audius offers to ask for.
  ///
  /// 480 rather than 1000: the largest place a cover is drawn is the full
  /// player's artwork, and even at 3x device pixel ratio a 480px source covers
  /// a 160pt square. `CoverArt` decodes down to the size it will paint anyway,
  /// so asking for 1000 would only spend bandwidth to throw pixels away.
  static const String preferredSize = '480x480';

  /// Every url worth trying for [artwork], best first, or empty for an item with
  /// no usable artwork.
  ///
  /// The head is the node the API named; the tail is the same path on each
  /// mirror. Nothing here checks whether a host is up -- that costs a request
  /// per candidate and the answer would be stale by the time the image loads.
  /// The list is a set of options for [CoverArt] to walk, not a promise that any
  /// of them will answer.
  static List<String> urlsFrom(Map<String, Object?>? artwork) {
    if (artwork == null) return const [];

    // Falls back through the smaller sizes: an older upload may carry only some
    // of them, and a smaller cover beats the placeholder.
    final primary =
        artwork.stringOrNull(preferredSize) ??
        artwork.stringOrNull('1000x1000') ??
        artwork.stringOrNull('150x150');
    if (primary == null) return const [];

    final primaryUri = Uri.tryParse(primary);
    // Unparseable, so there is no path to graft onto anything. Handing the
    // string back regardless leaves us no worse off than before mirrors existed.
    if (primaryUri == null || primaryUri.path.isEmpty) return [primary];

    // A Set literal, so a mirror that repeats the host we already have does not
    // become an attempt at a node that just failed. Insertion-ordered in Dart,
    // which is what keeps "best first" true.
    final candidates = {primary};
    for (final mirror in _mirrorsIn(artwork)) {
      final origin = Uri.tryParse(mirror);
      // `hasAuthority` is the check that matters: a mirror is only useful as a
      // scheme and a host to graft the path onto, and an entry that is neither
      // (a bare word, an empty string) would otherwise resolve to a relative
      // uri that fetches nothing.
      if (origin == null || !origin.hasAuthority) continue;
      candidates.add(
        origin
            .replace(path: primaryUri.path, query: primaryUri.hasQuery ? primaryUri.query : null)
            .toString(),
      );
    }
    return candidates.toList(growable: false);
  }

  /// The `mirrors` array, skipping anything in it that is not a string.
  ///
  /// Lenient where the rest of the parsing is strict, and the asymmetry is the
  /// point: a malformed field the app *needs* is a backend change worth failing
  /// loudly on, while artwork is decoration. Throwing here would turn one junk
  /// entry in a list of alternates into a screen that will not load.
  static List<String> _mirrorsIn(Map<String, Object?> artwork) {
    final value = artwork['mirrors'];
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty) entry,
    ];
  }
}
