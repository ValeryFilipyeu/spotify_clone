import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'image_byte_store.dart';

Future<ImageByteStore?> openImageByteStore() => FileImageByteStore.open();

/// Covers as files in a directory, under a budget in megabytes.
///
/// Lives in `getApplicationCacheDirectory()`, which settles three things without
/// code: the OS may reclaim it, it is not backed up, and uninstalling takes it.
/// A cache the system can delete needs no settings screen. The obligation that
/// comes with it is that any read may find the file gone -- which is just a miss.
///
/// Budget in bytes rather than files, because these are whatever a stranger's
/// server sends. Measured on live artwork a 480x480 cover averages 38 KB (worst
/// of twelve: 77 KB), so 32 MB holds roughly 840 against a heavy session of 300.
class FileImageByteStore implements ImageByteStore {
  FileImageByteStore(this.directory, {this.maxBytes = defaultMaxBytes});

  /// See the class doc: 32 MB, from measured cover sizes.
  static const int defaultMaxBytes = 32 * 1024 * 1024;

  /// How far under [maxBytes] a sweep goes. Without the gap a full cache would
  /// list the whole directory on every write to delete one file.
  static const double _sweepTo = 0.8;

  final Directory directory;
  final int maxBytes;

  /// In memory so a write need not stat the directory. Seeded by [open].
  int _bytesHeld = 0;

  int get bytesHeld => _bytesHeld;

  static Future<FileImageByteStore> open({int maxBytes = defaultMaxBytes}) async {
    final root = await getApplicationCacheDirectory();
    final directory = Directory('${root.path}/cover_images');
    await directory.create(recursive: true);

    final store = FileImageByteStore(directory, maxBytes: maxBytes);
    await store.measure();
    return store;
  }

  /// One directory listing per launch, so nothing after it needs one.
  Future<void> measure() async {
    var total = 0;
    await for (final entry in directory.list()) {
      if (entry is File) total += await entry.length();
    }
    _bytesHeld = total;
  }

  @override
  Future<Uint8List?> read(String url) async {
    final file = fileFor(url);
    try {
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      // The OS may sweep the directory at any moment; a vanished file is a miss.
      return null;
    }
  }

  @override
  Future<void> write(String url, Uint8List bytes) async {
    // Larger than the whole budget would be written and swept straight back out.
    if (bytes.length > maxBytes) return;

    final file = fileFor(url);
    final existing = await file.exists() ? await file.length() : 0;
    await file.writeAsBytes(bytes, flush: false);
    _bytesHeld += bytes.length - existing;

    if (_bytesHeld > maxBytes) await _sweep();
  }

  @override
  Future<void> delete(String url) async {
    final file = fileFor(url);
    try {
      if (!await file.exists()) return;
      _bytesHeld -= await file.length();
      await file.delete();
    } on FileSystemException {
      // Already gone; the next measure() corrects _bytesHeld.
    }
  }

  /// Deletes oldest-first until comfortably under budget.
  ///
  /// Oldest by *written*, not read: touching a timestamp on every cache hit is a
  /// disk write for having avoided a download. The cost is that a daily cover
  /// ages out like a one-off, which for artwork is a fair trade.
  Future<void> _sweep() async {
    final files = <({File file, DateTime modified, int length})>[];
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      try {
        final stat = await entry.stat();
        files.add((file: entry, modified: stat.modified, length: stat.size));
      } on FileSystemException {
        continue;
      }
    }
    files.sort((a, b) => a.modified.compareTo(b.modified));

    final target = (maxBytes * _sweepTo).round();
    for (final entry in files) {
      if (_bytesHeld <= target) break;
      try {
        await entry.file.delete();
        _bytesHeld -= entry.length;
      } on FileSystemException {
        continue;
      }
    }
  }

  /// A url as a filename. Hashed because urls contain separators and outrun the
  /// 255-byte limit on a path component; SHA-1 only because it is already in the
  /// binary, and nothing here is a security decision.
  ///
  /// Visible to tests: "any url lands on exactly one file" is part of the
  /// promise, and asserting it otherwise means guessing at filenames.
  @visibleForTesting
  File fileFor(String url) => File('${directory.path}/${sha1.convert(utf8.encode(url))}');
}
