import 'dart:convert';

import '../../catalog/models/catalog_json.dart';
import '../../catalog/models/track.dart';
import '../../network/json_reader.dart';
import '../../storage/key_value_store.dart';
import 'playback_queue_repository.dart';

/// The saved queue as JSON in a [KeyValueStore], keyed per account
/// (`playback_queue:<userId>`), alongside the volume and crossfade preferences.
///
/// The tracks are written by the same codec the offline catalog cache uses -- see
/// [encodeTrack]. Worth insisting on: a second, private way of writing a [Track]
/// down would be two formats to keep in step, and they would drift the first time
/// a field was added to one of them.
///
/// Anything unreadable is treated as no saved queue at all. A player that refused
/// to start because a stale session would not parse is a worse outcome than one
/// that quietly begins from nothing, and the very next thing played overwrites it.
class LocalPlaybackQueueRepository implements PlaybackQueueRepository {
  const LocalPlaybackQueueRepository(this._store);

  final KeyValueStore _store;

  /// Bumped if the shape below changes, so an old payload reads as absent rather
  /// than as something it is not. Same reasoning as [CatalogCacheStore], and
  /// necessary for the same reason: the build that wrote this is not the build
  /// reading it.
  static const int _version = 1;

  static String _queueKey(String userId) => 'playback_queue:$userId';
  static String _positionKey(String userId) => 'playback_position:$userId';

  @override
  Future<SavedQueue?> fetchQueue(String userId) async {
    final raw = await _store.read(_queueKey(userId));
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      if (json['v'] != _version) return null;

      final queue = _tracksIn(json, 'queue');
      // An empty queue is not a session. Nothing writes one, but a truncated file
      // could produce one, and restoring it would leave a player that thinks it
      // has something and cannot say what.
      if (queue.isEmpty) return null;

      final source = json['sourceQueue'] == null ? null : _tracksIn(json, 'sourceQueue');
      final where = await _readPosition(userId);

      return SavedQueue(
        queue: queue,
        sourceQueue: source,
        // Clamped, because the two keys can disagree: the position is written far
        // more often than the tracklist, so a crash between the two can leave an
        // index pointing past the end of a queue that has since shrunk.
        currentIndex: where.index.clamp(0, queue.length - 1),
        position: where.position,
        isShuffled: json.boolean('isShuffled'),
      );
    } on FormatException {
      return null;
    } on JsonFormatError {
      return null;
    }
  }

  @override
  Future<void> saveQueue(String userId, SavedQueue queue) => _store.write(
    _queueKey(userId),
    jsonEncode({
      'v': _version,
      'queue': [for (final track in queue.queue) encodeTrack(track)],
      // Omitted when it is the same list, which is every session nobody shuffled.
      if (queue.sourceQueue != null)
        'sourceQueue': [for (final track in queue.sourceQueue!) encodeTrack(track)],
      'isShuffled': queue.isShuffled,
    }),
  );

  @override
  Future<void> savePosition(
    String userId, {
    required int currentIndex,
    required Duration position,
  }) => _store.write(
    _positionKey(userId),
    jsonEncode({'index': currentIndex, 'ms': position.inMilliseconds}),
  );

  @override
  Future<void> clear(String userId) async {
    await _store.delete(_queueKey(userId));
    await _store.delete(_positionKey(userId));
  }

  Future<({int index, Duration position})> _readPosition(String userId) async {
    final raw = await _store.read(_positionKey(userId));
    if (raw == null) return (index: 0, position: Duration.zero);
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return (index: 0, position: Duration.zero);
      final ms = json['ms'];
      final index = json['index'];
      return (
        index: index is num ? index.toInt() : 0,
        position: Duration(milliseconds: ms is num ? ms.toInt() : 0),
      );
    } on FormatException {
      return (index: 0, position: Duration.zero);
    }
  }

  List<Track> _tracksIn(Map<String, Object?> json, String key) => [
    for (final (index, track) in json.objectList(key).indexed)
      decodeTrack(track, at: '$key[$index]'),
  ];
}
