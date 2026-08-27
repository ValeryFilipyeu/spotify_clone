import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_audio/just_audio.dart';

import '../../../storage/key_value_store.dart';
import '../audio_cache.dart';
import 'audio_blob_store.dart';

/// The web half of [AudioCache]: the last [keepTracks] tracks played, kept whole
/// in browser storage and played back from there with no network.
///
/// **A track is fetched twice the first time it is played.** just_audio on the
/// web loads from a url, so bytes are only playable once they are a complete
/// object -- there is no equivalent of the mobile source that streams to the
/// player and writes to disk in one pass. Playing from the network while
/// downloading alongside it keeps playback instant and costs one extra fetch per
/// newly played track, and nothing on any replay. Downloading first instead would
/// make every first play wait for the whole file.
///
/// Recency is kept here rather than read back from storage: the Cache API records
/// nothing like a modification time, and "oldest" has to mean least recently
/// *played* for a replay to count.
class WebAudioCache implements AudioCache {
  WebAudioCache(this._blobs, this._played, {this.keepTracks = 5, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// One JSON object of url -> epoch millis, not a key per track: it is rewritten
  /// whole on every play, and shared_preferences rewrites its whole file anyway.
  static const String _playedKey = 'audio_cache_played';

  final AudioBlobStore _blobs;
  final KeyValueStore _played;

  /// See [AudioCache] for why this is a count and not a byte budget.
  final int keepTracks;

  final DateTime Function() _now;

  /// Live handles from [AudioBlobStore.localUrlFor], so replaying a track does
  /// not allocate a second copy of the same bytes. Bounded by [keepTracks], since
  /// eviction releases them.
  final Map<String, String> _localUrls = {};

  /// Urls with a download in flight, so the two crossfade players cannot both
  /// fetch one track. Unlike the mobile cache this clears in a `finally`: the
  /// download is one awaited call here, so an abandoned one cannot leave the url
  /// marked forever.
  final Set<String> _downloading = {};

  @override
  Future<AudioSource> sourceFor(String url) async {
    final local = await _localUrlFor(url);
    if (local != null) {
      await _touch(url);
      return AudioSource.uri(Uri.parse(local));
    }

    unawaited(_download(url));
    return AudioSource.uri(Uri.parse(url));
  }

  /// Deletes all but the [keepTracks] most recently played.
  @visibleForTesting
  Future<void> evict() async {
    final stored = await _blobs.keys();
    final played = await _readPlayed();

    // Anything stored with no timestamp is treated as older than anything with
    // one. It outlived the index; calling it new instead would make it immortal.
    final ranked = [for (final url in stored) (url: url, at: played[url] ?? 0)]
      ..sort((a, b) => a.at.compareTo(b.at));

    final excess = ranked.length - keepTracks;
    if (excess <= 0) return;

    for (final entry in ranked.take(excess)) {
      await _blobs.delete(entry.url);
      final local = _localUrls.remove(entry.url);
      if (local != null) _blobs.release(local);
    }

    // Rewritten from what survived, which is also the only thing that drops
    // timestamps for tracks no longer stored.
    await _writePlayed({for (final entry in ranked.skip(excess)) entry.url: entry.at});
  }

  Future<String?> _localUrlFor(String url) async {
    final existing = _localUrls[url];
    if (existing != null) return existing;

    final created = await _blobs.localUrlFor(url);
    if (created != null) _localUrls[url] = created;
    return created;
  }

  Future<void> _download(String url) async {
    if (!_downloading.add(url)) return;
    try {
      await _blobs.download(url);
      await _touch(url);
      await evict();
    } on Object {
      // Playback already has the network source; the cost is a miss next time.
    } finally {
      _downloading.remove(url);
    }
  }

  Future<void> _touch(String url) async {
    final played = await _readPlayed();
    played[url] = _now().millisecondsSinceEpoch;
    await _writePlayed(played);
  }

  Future<Map<String, int>> _readPlayed() async {
    final raw = await _played.read(_playedKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final entry in decoded.entries)
          if (entry.value case final int at) entry.key: at,
      };
    } on Object {
      // `on Object`, not FormatException: a payload that parses as something
      // other than an object fails the cast instead. Either way the history is
      // gone, which costs one round of over-eager eviction.
      return {};
    }
  }

  Future<void> _writePlayed(Map<String, int> played) async {
    try {
      await _played.write(_playedKey, jsonEncode(played));
    } on Object {
      // Storage full or unavailable. Eviction gets less accurate, not wrong.
    }
  }
}
