import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_cache.dart';

// just_audio marks LockCachingAudioSource @experimental: it works and is widely
// used, but its author reserves the right to change or drop it. Acknowledged
// here rather than silenced everywhere, and it is the reason this class exists
// as a seam at all -- if the class goes away, what has to be rewritten is one
// method in one file, and nothing above AudioCache notices.
// ignore_for_file: experimental_member_use

Future<AudioCache?> openAudioCache({int keepTracks = 5}) =>
    FileAudioCache.open(keepTracks: keepTracks);

/// Played tracks as files, the newest [keepTracks] of them.
///
/// ## What does the downloading
///
/// just_audio's own [LockCachingAudioSource], which streams a track to the player
/// and writes it to disk in the same pass -- so the first play is not slower and
/// the second needs no network. Nothing here re-implements that; what this class
/// adds is where the files go, how many are kept, and the two cases the library
/// leaves to the caller.
///
/// **A finished download goes back to the same class, not to a file source.**
/// The obvious shortcut is `AudioSource.uri(Uri.file(path))`, and it is wrong on
/// iOS in a way nothing here would notice: AVFoundation works out a local file's
/// container format from its path *extension*, these files are named by hash and
/// have none, so `AVURLAsset` refuses them with
/// `AVErrorFileFormatNotRecognized` (-11828). Measured, not deduced -- every
/// cached track loaded, showed in the player and played silence. Handed back to
/// [LockCachingAudioSource] instead, the bytes are served through just_audio's
/// own stream path together with the content type it recorded beside them while
/// downloading, so nothing has to guess. It makes no request either: its
/// `request()` short-circuits to the file the moment the cache file exists,
/// which is what keeps a cached track playable with no network at all.
///
/// Naming the files `<hash>.mp3` would also work, and would be a worse fix: the
/// extension would have to be guessed from a MIME type that only arrives with
/// the first response, so it would mean renaming the file after the download and
/// keeping a MIME-to-extension table that is wrong for the first format this
/// catalog does not serve.
///
/// **Two players must never download the same track at once.** The library
/// downloads to `<file>.part` and renames it into place when it finishes, so a
/// half-written file is never mistaken for a whole one -- but two sources writing
/// one `.part` would interleave and the rename would publish the result. The
/// window is narrow (it needs repeat-one, crossfade, and a track being heard for
/// the first time) and the consequence is a corrupt file served confidently ever
/// after, so [_downloading] closes it: the second asker streams without caching.
///
/// The cost of that guard is small and worth stating: a download abandoned
/// part-way -- skipped before it finished -- leaves its url marked in-flight for
/// the rest of the session, so it will not be cached again until the app
/// restarts. Better than the alternative, which is a corrupt track.
class FileAudioCache implements AudioCache {
  FileAudioCache(this.directory, {this.keepTracks = 5, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final Directory directory;

  /// How many tracks survive. See [AudioCache] for why this is a count and not a
  /// byte budget.
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
      // Touched so that "oldest" means least recently *played* rather than least
      // recently downloaded. Replaying a cached track writes no bytes, so without
      // this a favourite could be evicted the moment five newer tracks appeared.
      // One metadata write per track start, which is nothing beside the megabytes
      // this is deciding the fate of.
      await _touch(file);
      // Nothing left to download; see the class doc for why this is still the
      // caching source and not a plain file.
      return LockCachingAudioSource(Uri.parse(url), cacheFile: file);
    }

    if (_downloading.contains(url)) return AudioSource.uri(Uri.parse(url));

    _downloading.add(url);
    final source = LockCachingAudioSource(Uri.parse(url), cacheFile: file);
    source.downloadProgressStream
        .firstWhere((progress) => progress >= 1)
        .then((_) => _downloading.remove(url))
        .ignore();

    // Before the new one lands rather than after, so the cache is never briefly
    // over its limit -- and because the file being downloaded does not exist yet,
    // it cannot evict itself.
    await evict();
    return source;
  }

  /// Deletes all but the [keepTracks] most recently played.
  @visibleForTesting
  Future<void> evict() async {
    final tracks = <({File file, DateTime played})>[];
    await for (final entry in directory.list()) {
      // A download in progress, and the type it will be. Neither is a track yet,
      // and deleting a `.part` would sabotage the download writing it.
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
    // One short of the limit, because the caller is about to add one.
    for (final track in tracks.take(tracks.length - (keepTracks - 1))) {
      await _deleteWithCompanions(track.file);
    }
  }

  /// A url as a filename, hashed for the reason given on [FileImageByteStore].
  @visibleForTesting
  File fileFor(String url) => File('${directory.path}/${sha1.convert(utf8.encode(url))}');

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(_now());
    } on FileSystemException {
      // Some filesystems refuse this. The cost is an eviction order that follows
      // download time instead of play time, which is not worth failing playback
      // over.
    }
  }

  /// A cached track is up to three files: the audio, its recorded mime type, and
  /// possibly an abandoned partial download. Leaving either companion behind
  /// would slowly fill the directory with litter no listing counts.
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
