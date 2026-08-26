import 'dart:convert';

import '../../catalog/models/catalog_json.dart';
import '../../catalog/models/track.dart';
import '../../network/json_reader.dart';
import '../../storage/key_value_store.dart';
import 'playback_queue_repository.dart';

/// The saved queue as JSON in a [KeyValueStore], keyed per account.
///
/// Tracks go through the same codec as the offline catalog cache ([encodeTrack]):
/// a second private format would be two things to keep in step, and they would
/// drift the first time a field was added to one.
///
/// Anything unreadable reads as no saved queue. Refusing to start over a stale
/// session is worse than starting from nothing.
class LocalPlaybackQueueRepository implements PlaybackQueueRepository {
  const LocalPlaybackQueueRepository(this._store);

  final KeyValueStore _store;

  /// Bumped when the shape changes, so an old payload reads as absent: the build
  /// that wrote this is not the build reading it.
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
      // Nothing writes one, but a truncated file could -- and restoring it
      // leaves a player that thinks it has something and cannot say what.
      if (queue.isEmpty) return null;

      final source = json['sourceQueue'] == null ? null : _tracksIn(json, 'sourceQueue');
      final where = await _readPosition(userId);

      return SavedQueue(
        queue: queue,
        sourceQueue: source,
        // The two keys can disagree: position is written far more often, so a
        // crash between them can leave an index past the end of the queue.
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
      // Omitted when it is the same list -- every unshuffled session.
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
