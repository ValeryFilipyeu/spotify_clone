import 'dart:typed_data';

import 'image_byte_store_stub.dart' if (dart.library.io) 'image_byte_store_io.dart' as platform;

/// Image bytes on the device, keyed by url.
///
/// Separate from [KeyValueStore] because shared_preferences rewrites its whole
/// file on every change -- fine for JSON, absurd for 30 MB of JPEG.
///
/// Keyed by url, not by anything the catalog understands, so the same bytes on
/// four Audius hosts are four entries. That sounds wasteful and is correct:
/// [CoverArt] moves host precisely when one stops answering, which an entry keyed
/// by "the cover for playlist X" could not express.
abstract class ImageByteStore {
  /// The saved bytes for [url], or null if there are none.
  Future<Uint8List?> read(String url);

  Future<void> write(String url, Uint8List bytes);

  /// Drops one entry. Called when what was saved turns out not to decode.
  Future<void> delete(String url);
}

/// Opens the device's cover cache. Null on the web, and not a gap: the browser
/// already disk-caches images by their own headers. Everywhere else Flutter's
/// [ImageCache] is memory-only and dies with the process.
Future<ImageByteStore?> openImageByteStore() => platform.openImageByteStore();
