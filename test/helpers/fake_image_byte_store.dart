import 'dart:convert';
import 'dart:typed_data';

import 'package:spotify_clone/storage/image_byte_store.dart';

/// A 2x2 green PNG, 74 bytes.
///
/// Generated rather than checked in as a file so these tests stay pure Dart, and
/// a real encoded PNG rather than arbitrary bytes because the point of most of
/// them is that what comes out of the store actually *decodes* -- which nothing
/// but a genuine image can demonstrate.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGOQ3RnyH4QZYAwASVQIpWfouVwAAAAASUVORK5CYII=',
);

/// Bytes that are the right shape for a cache entry and cannot possibly decode.
final Uint8List notAnImage = Uint8List.fromList(utf8.encode('half a file, honestly'));

/// An in-memory [ImageByteStore] that records what it was asked.
class FakeImageByteStore implements ImageByteStore {
  final Map<String, Uint8List> files = {};

  final List<String> reads = [];
  final List<String> writes = [];
  final List<String> deletes = [];

  /// Stands in for a full disk, or a cache directory the OS took away.
  bool failWrites = false;

  @override
  Future<Uint8List?> read(String url) async {
    reads.add(url);
    return files[url];
  }

  @override
  Future<void> write(String url, Uint8List bytes) async {
    writes.add(url);
    if (failWrites) throw StateError('no room');
    files[url] = bytes;
  }

  @override
  Future<void> delete(String url) async {
    deletes.add(url);
    files.remove(url);
  }
}
