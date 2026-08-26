import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_cache.dart';

// LockCachingAudioSource is @experimental upstream. Acknowledged here rather
// than silenced everywhere; it is also why AudioCache is a seam, so losing the
// class costs one method in one file.
// ignore_for_file: experimental_member_use

Future<AudioCache?> openAudioCache({int keepTracks = 5}) =>
    FileAudioCache.open(keepTracks: keepTracks);

/// Played tracks as files, the newest [keepTracks] of them.
///
/// The downloading is just_audio's [LockCachingAudioSource], which streams to the
/// player and writes to disk in one pass. This class only decides where the files
/// go, how many are kept, and the two cases the library leaves to the caller.
///
/// **A finished download goes back to the same class, not to a file source.**
/// `AudioSource.uri(Uri.file(path))` is the obvious shortcut and it is silently
/// broken on iOS: AVFoundation reads a local file's format off its path
/// extension, these are named by hash, and AVURLAsset refuses them with -11828 --
/// so a cached track loads, appears in the player and plays silence. Going back
/// through [LockCachingAudioSource] carries the recorded MIME type with the
/// bytes, and makes no request, since its `request()` short-circuits to the file.
///
/// **Two players must never download the same track at once.** Both would write
/// one `.part` and the rename would publish the interleaved result, so
/// [_downloading] sends the second asker straight to the network. The cost: a
/// download abandoned part-way stays marked in-flight until the app restarts.
class FileAudioCache implements AudioCache {
  FileAudioCache(this.directory, {this.keepTracks = 5, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final Directory directory;

  /// See [AudioCache] for why this is a count and not a byte budget.
  final int keepTracks;

  final DateTime Function() _now;

  /// Urls with a download in flight. See the class doc.
  final Set<String> _downloading = {};

  static Future<FileAudioCache> open({int keepTracks = 5}) async {
    final root = await getApplicationCacheDirectory();
    final directory = Directory('${root.path}/cached_audio');
    await directory.create(recursive: true);
    return FileAudioCache(directory, keepTracks: keepTracks);
  }

  @override
  Future<AudioSource> sourceFor(String url) async {
    final file = fileFor(url);

    if (await file.exists()) {
      // Makes "oldest" mean least recently played, not least recently
      // downloaded -- a replay writes no bytes and would otherwise age out.
      await _touch(file);
      // Still the caching source, not a plain file: see the class doc.
      return LockCachingAudioSource(Uri.parse(url), cacheFile: file);
    }

    if (_downloading.contains(url)) return AudioSource.uri(Uri.parse(url));

    _downloading.add(url);
    final source = LockCachingAudioSource(Uri.parse(url), cacheFile: file);
    source.downloadProgressStream
        .firstWhere((progress) => progress >= 1)
        .then((_) => _downloading.remove(url))
        .ignore();

    // Before the new one lands, so the cache is never briefly over its limit.
    await evict();
    return source;
  }

  /// Deletes all but the [keepTracks] most recently played.
  @visibleForTesting
  Future<void> evict() async {
    final tracks = <({File file, DateTime played})>[];
    await for (final entry in directory.list()) {
      // Not tracks yet, and deleting a `.part` sabotages a live download.
      if (entry is! File || entry.path.endsWith('.part') || entry.path.endsWith('.mime')) {
        continue;
      }
      try {
        tracks.add((file: entry, played: (await entry.stat()).modified));
      } on FileSystemException {
        continue;
      }
    }
    if (tracks.length < keepTracks) return;

    tracks.sort((a, b) => a.played.compareTo(b.played));
    for (final track in tracks.take(tracks.length - (keepTracks - 1))) {
      await _deleteWithCompanions(track.file);
    }
  }

  /// A url as a filename. Hashed: see [FileImageByteStore].
  @visibleForTesting
  File fileFor(String url) => File('${directory.path}/${sha1.convert(utf8.encode(url))}');

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(_now());
    } on FileSystemException {
      // Some filesystems refuse it. Not worth failing playback over.
    }
  }

  /// A track is up to three files: audio, `.mime`, and maybe an abandoned
  /// `.part`. Companions left behind are litter no listing counts.
  Future<void> _deleteWithCompanions(File file) async {
    for (final path in [file.path, '${file.path}.mime', '${file.path}.part']) {
      try {
        final companion = File(path);
        if (await companion.exists()) await companion.delete();
      } on FileSystemException {
        continue;
      }
    }
  }
}
