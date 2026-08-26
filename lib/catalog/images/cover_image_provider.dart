import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../../storage/image_byte_store.dart';

/// How the bytes are fetched when they are not on disk. Injected so a test can
/// answer without a network.
typedef ImageBytesFetch = Future<Uint8List> Function(Uri url);

/// The provider [CoverArt] puts in the tree for one url.
///
/// With no [store] -- on the web, and in tests -- this is exactly the plain
/// [NetworkImage] used before caching existed. The caching path is an addition
/// where it helps, not a replacement.
ImageProvider coverImageProvider(String url, {ImageByteStore? store, ImageBytesFetch? fetch}) {
  if (store == null) {
    return NetworkImage(
      url,
      // Web only, and load-bearing there; ignored elsewhere. See CoverArt.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    );
  }
  return CachedNetworkImage(url, store: store, fetch: fetch ?? fetchOverHttp);
}

/// A cover read from disk if it is there, fetched and saved if it is not.
///
/// A provider rather than a cache in front of one, because choosing between
/// [FileImage] and [NetworkImage] is an async question and `build` is not.
///
/// Two things [CoverArt]'s host-walk depends on and this must preserve:
///
///  * **A failure is reported as one.** A bad host resolving to a blank image
///    would never reach `errorBuilder`, and the walk would stop at the first dead
///    node. So a non-2xx throws, with [NetworkImage]'s own exception type.
///  * **Equality is stable across rebuilds.** `evict()` finds entries by key, so
///    an unstable one would strand the failure in [ImageCache] for ever.
@immutable
class CachedNetworkImage extends ImageProvider<CachedNetworkImage> {
  const CachedNetworkImage(this.url, {required this.store, required this.fetch});

  final String url;
  final ImageByteStore store;
  final ImageBytesFetch fetch;

  @override
  Future<CachedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedNetworkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: key._load(decode),
      scale: 1,
      debugLabel: url,
      informationCollector: () => [DiagnosticsProperty<String>('Image url', url)],
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final saved = await store.read(url);
    if (saved != null) {
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(saved));
      } on Object {
        // A truncated write. Dropping it is what makes this self-healing.
        await store.delete(url);
      }
    }

    final bytes = await fetch(Uri.parse(url));
    // Awaited: one file write against a round trip already paid, in exchange for
    // tests that do not race a background save.
    try {
      await store.write(url, bytes);
    } on Object {
      // Not a reason to fail an image we are holding.
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImage &&
      other.url == url &&
      identical(other.store, store) &&
      other.fetch == fetch;

  @override
  int get hashCode => Object.hash(url, identityHashCode(store), fetch);

  @override
  String toString() => 'CachedNetworkImage("$url")';
}

/// The default [ImageBytesFetch]. Refusals throw [NetworkImageLoadException],
/// the same type [NetworkImage] raises.
///
/// [client] is a seam purely so this can be tested: it is the only part of the
/// caching path that talks to a real network, and it was unexercised until it
/// had one.
Future<Uint8List> fetchOverHttp(Uri url, {http.Client? client}) async {
  // The widget already gives up after six seconds; this just stops the abandoned
  // request from holding a connection open behind it.
  final get = client?.get(url) ?? http.get(url);
  final response = await get.timeout(const Duration(seconds: 10));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw NetworkImageLoadException(statusCode: response.statusCode, uri: url);
  }
  if (response.bodyBytes.isEmpty) {
    // A 200 with no body: a refusal. The decoder's complaint would name a codec
    // instead of a host.
    throw NetworkImageLoadException(statusCode: response.statusCode, uri: url);
  }
  return response.bodyBytes;
}
