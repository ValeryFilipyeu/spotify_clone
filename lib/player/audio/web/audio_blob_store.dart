/// Where the web build keeps whole tracks, and how it hands them to the player.
///
/// A seam so [WebAudioCache] can be exercised off-browser: everything that knows
/// about the Cache API lives in the one implementation behind it.
abstract class AudioBlobStore {
  /// Downloads [url] and stores it whole. Throws if it could not be fetched.
  Future<void> download(String url);

  /// A url the player can load the stored bytes from, or null if [url] was never
  /// stored. The caller owns the result and must [release] it.
  Future<String?> localUrlFor(String url);

  Future<void> delete(String url);

  /// Every url currently stored.
  Future<List<String>> keys();

  /// Frees a url handed out by [localUrlFor].
  void release(String localUrl);
}
