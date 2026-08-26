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
/// With no [store] -- on the web, and in every test that does not ask for one --
/// this is the plain [NetworkImage] the widget used before any of this existed,
/// including its web fallback strategy. That is the point of the null: the
/// caching path is an addition on platforms that benefit, not a replacement of
/// something that already worked.
ImageProvider coverImageProvider(String url, {ImageByteStore? store, ImageBytesFetch? fetch}) {
  if (store == null) {
    return NetworkImage(
      url,
      // Web only, and load-bearing there -- see the note in CoverArt. Ignored
      // everywhere else, so it costs nothing to keep on both paths.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    );
  }
  return CachedNetworkImage(url, store: store, fetch: fetch ?? fetchOverHttp);
}

/// A cover read from disk if it is there, and fetched and saved if it is not.
///
/// ## Why an ImageProvider rather than a cache in front of one
///
/// The obvious shape -- ask the store, then hand the answer to [FileImage] or
/// [NetworkImage] -- cannot be built, because choosing between them is an
/// asynchronous question and `build` is synchronous. A provider is the seam
/// Flutter gives you for exactly this: [loadImage] is allowed to take its time,
/// and everything above it (the fade, the retry walk, the eviction) goes on
/// working without knowing where the bytes came from.
///
/// ## What it must not break
///
/// [CoverArt] walks a list of hosts when one fails, and that walk depends on two
/// behaviours of the thing in its tree:
///
///  * **A failure has to be reported as one.** If a bad host resolved to a blank
///    image instead of an error, `errorBuilder` would never run and the walk
///    would stop at the first dead node. So a non-2xx throws, exactly as
///    [NetworkImage] does, and with the same exception type.
///  * **Equality has to be stable across rebuilds.** `evict()` finds the entry to
///    remove by key, so a provider that compared unequal to the identical one
///    built a frame earlier would leave the failed entry in [ImageCache] for ever
///    -- and cycling back to that host would be answered out of it with the old
///    failure.
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
        // Saved bytes that will not decode: a write cut short by the process
        // dying, or a file the OS truncated. Dropping it is what makes that
        // self-healing -- otherwise this cover is broken until the entry ages
        // out, and re-fetching it would never be tried.
        await store.delete(url);
      }
    }

    final bytes = await fetch(Uri.parse(url));
    // Awaited rather than left running. It delays the first paint by one file
    // write on a cover that has just cost a network round trip, and in exchange
    // every test of this is deterministic instead of racing a background save.
    try {
      await store.write(url, bytes);
    } on Object {
      // A cache that cannot be written to is a cache. It is not a reason to fail
      // an image we are holding.
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

/// The default [ImageBytesFetch].
///
/// Throws [NetworkImageLoadException] on a refusal -- Flutter's own type for
/// this, and the same one [NetworkImage] raises, so nothing downstream has to
/// learn a second way of hearing that a cover did not arrive.
/// [client] exists so this can be tested at all: it is the one piece of the
/// caching path that talks to a real network, and without a seam the tests would
/// cover everything around it and leave the part that actually runs in
/// production unexercised. (Which is precisely what happened -- a sabotage that
/// deleted the status check below broke nothing.)
Future<Uint8List> fetchOverHttp(Uri url, {http.Client? client}) async {
  // A ceiling on the whole request, matching ApiClient's. The widget gives up on
  // a stalled cover after six seconds and moves to the next host, so this is not
  // what makes the UI responsive -- it is what stops the abandoned request from
  // holding a connection open indefinitely behind it.
  final get = client?.get(url) ?? http.get(url);
  final response = await get.timeout(const Duration(seconds: 10));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw NetworkImageLoadException(statusCode: response.statusCode, uri: url);
  }
  if (response.bodyBytes.isEmpty) {
    // A 200 with nothing in it. Treated as a refusal rather than passed to the
    // decoder, whose complaint would name a codec instead of a host.
    throw NetworkImageLoadException(statusCode: response.statusCode, uri: url);
  }
  return response.bodyBytes;
}
