import 'dart:typed_data';

import 'image_byte_store_stub.dart' if (dart.library.io) 'image_byte_store_io.dart' as platform;

/// Image bytes kept on the device, keyed by the url they came from.
///
/// The counterpart to [KeyValueStore], and separate from it for one reason:
/// shared_preferences holds its whole contents in memory and rewrites the file
/// when anything changes, which is fine for a few hundred kilobytes of JSON and
/// absurd for thirty megabytes of JPEG. Bytes want files.
///
/// Deliberately keyed by url rather than by anything the catalog understands. A
/// cover is identified by where it came from, and the same bytes served from four
/// Audius hosts are four entries here -- which sounds wasteful and is the correct
/// behaviour: the walk in [CoverArt] moves to another host precisely when the
/// first one stopped answering, and an entry keyed by "the cover for playlist X"
/// could not tell those apart.
abstract class ImageByteStore {
  /// The saved bytes for [url], or null if there are none.
  Future<Uint8List?> read(String url);

  Future<void> write(String url, Uint8List bytes);

  /// Drops one entry. Called when what was saved turns out not to decode.
  Future<void> delete(String url);
}

/// Opens the device's cover cache, or answers null where there is nowhere
/// sensible to put one.
///
/// Null on the web, and that is not a gap. A browser already keeps a disk cache
/// of every image it fetches, honouring the response's own cache headers -- doing
/// it again in IndexedDB would be a slower copy of something the platform does
/// properly. Everywhere else Flutter's [ImageCache] is memory-only and dies with
/// the process, which is exactly the case this exists for.
Future<ImageByteStore?> openImageByteStore() => platform.openImageByteStore();
