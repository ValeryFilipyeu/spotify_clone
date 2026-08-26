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
/// ## Where they go, and why it matters
///
/// `getApplicationCacheDirectory()`, which is the OS's designated
/// throw-this-away-if-you-need-the-space location (`Library/Caches` on Apple
/// platforms, `cacheDir` on Android). That is the right home for exactly this,
/// and choosing it settles three things at once that would otherwise each need
/// code: the OS may reclaim the lot under storage pressure, none of it is backed
/// up to iCloud or Google Drive, and uninstalling takes it with it. A cache the
/// system is allowed to delete is a cache nobody has to write a settings screen
/// for.
///
/// The one obligation that comes with it: every read has to cope with the file
/// having vanished between one launch and the next. It does -- a miss is just a
/// miss.
///
/// ## The budget
///
/// Measured on live Audius artwork, a 480x480 cover averages 38 KB and the
/// largest of twelve sampled was 77 KB. [defaultMaxBytes] is 32 MB, so roughly
/// 840 covers at the average and 430 at the worst -- against a heavy session that
/// might touch 300 (a home screen is 40, and an album page can hold one per
/// track, since Audius artwork is per-upload rather than per-album).
///
/// Bytes rather than a file count, which is what [CatalogCacheStore] uses. There
/// the entries are the app's own JSON and predictable; here they are whatever a
/// stranger's server sends, so counting them would be measuring the wrong thing.
class FileImageByteStore implements ImageByteStore {
  FileImageByteStore(this.directory, {this.maxBytes = defaultMaxBytes});

  /// See the class doc: 32 MB, from measured cover sizes.
  static const int defaultMaxBytes = 32 * 1024 * 1024;

  /// How far under [maxBytes] an eviction sweeps.
  ///
  /// Without the gap, a full cache would sweep the directory on every single
  /// write for the sake of deleting one file. Clearing a fifth of it instead
  /// makes that rare.
  static const double _sweepTo = 0.8;

  final Directory directory;
  final int maxBytes;

  /// Kept in memory so a write does not have to stat the directory to find out
  /// whether it is over budget. Seeded by the one listing [open] does.
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

  /// Counts what is already on disk. One directory listing per launch, so that
  /// nothing after it has to.
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
      // The OS may have swept the directory out from under us at any moment --
      // see the class doc. A vanished file is a miss, not a failure.
      return null;
    }
  }

  @override
  Future<void> write(String url, Uint8List bytes) async {
    // Nothing that cannot possibly fit: a single file larger than the whole
    // budget would be written and then immediately swept, which is a lot of I/O
    // to accomplish nothing.
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
      // Already gone. Nothing to do, and _bytesHeld is corrected by the next
      // measure() at the latest.
    }
  }

  /// Deletes oldest-first until comfortably under budget.
  ///
  /// Oldest by *written*, not by last read. Reading a file to find out it is
  /// popular and then writing its timestamp back would mean a disk write every
  /// time a cover is shown from cache -- a strange price for having avoided a
  /// download. What it costs is that a cover you look at daily is evicted on the
  /// same schedule as one you saw once, and for artwork, where write order
  /// roughly follows browse order anyway, that is a fair trade.
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

  /// A url as a filename.
  ///
  /// Hashed because urls are longer than filesystems allow (Audius covers run to
  /// 110 characters and every path component is capped at 255 bytes) and contain
  /// separators. SHA-1 from `package:crypto`, which is already compiled into this
  /// app -- just_audio and google_fonts both depend on it -- so declaring it
  /// directly adds a line to the pubspec and nothing to the binary. Not a
  /// security decision: this is a filename, and what is wanted from it is that
  /// two different urls do not collide.
  /// Exposed to tests because the mapping is part of what this class promises --
  /// that any url, of any length, lands on exactly one file -- and asserting it
  /// from outside otherwise means guessing at filenames.
  @visibleForTesting
  File fileFor(String url) => File('${directory.path}/${sha1.convert(utf8.encode(url))}');
}
