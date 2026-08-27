import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'audio_blob_store.dart';

/// [AudioBlobStore] on the browser's Cache API.
///
/// Cache API and not IndexedDB because what has to survive is a `fetch` result
/// with its content type, and reading one back as a Blob is exactly what
/// [web.URL.createObjectURL] takes.
///
/// The content type matters as much here as it does on iOS, for the same reason:
/// a blob url is playable because the blob knows it is `audio/mpeg`. Bytes stored
/// without it play silence.
class CacheApiBlobStore implements AudioBlobStore {
  CacheApiBlobStore._(this._cache);

  static const String _cacheName = 'spotify_clone_audio';

  final web.Cache _cache;

  /// Opens the store, or null where there is no Cache API: it is gated on a
  /// secure context, which plain http on a LAN address is not.
  static Future<CacheApiBlobStore?> open() async {
    if (!web.window.has('caches')) return null;
    try {
      return CacheApiBlobStore._(await web.window.caches.open(_cacheName).toDart);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> download(String url) async {
    // Fetched and re-wrapped rather than handed to `cache.add`: the stream url
    // answers 302 to a signed location that expires, and what has to be stored
    // is the bytes at the end of it, keyed by the url the player will ask for.
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) throw StateError('audio download failed: HTTP ${response.status}');

    // Response-from-Blob takes its content type from the blob, which took it
    // from the fetch. See the class doc for why that is the load-bearing part.
    final blob = await response.blob().toDart;
    await _cache.put(url.toJS, web.Response(blob)).toDart;
  }

  @override
  Future<String?> localUrlFor(String url) async {
    final response = await _cache.match(url.toJS).toDart;
    if (response == null) return null;
    return web.URL.createObjectURL(await response.blob().toDart);
  }

  @override
  Future<void> delete(String url) async {
    await _cache.delete(url.toJS).toDart;
  }

  @override
  Future<List<String>> keys() async {
    final requests = (await _cache.keys().toDart).toDart;
    return [for (final request in requests) request.url];
  }

  @override
  void release(String localUrl) => web.URL.revokeObjectURL(localUrl);
}
