/// The catalog's domain models as JSON.
///
/// Two things read and write it: the offline catalog cache, and the saved
/// playback session that survives the app being closed. It lives beside the
/// models rather than inside either of them for that reason -- the second
/// consumer is what turned "how the offline cache happens to store a Track" into
/// "how this app writes a Track down".
///
/// The id-keyed collections at the bottom are still the cache's alone; a session
/// is an ordered list, not a lookup.
///
/// A codec of its own rather than `toJson`/`fromJson` on the models, for the
/// same reason Audius' payloads are read by DTOs and not by the models: a model
/// is what the app thinks in, and how one data source happens to write it to
/// disk is that source's business. Put on the models, serialisation would be
/// inherited by every consumer of them and would quietly become *the app's*
/// format -- a promise nobody set out to make, and one that makes renaming a
/// field a migration.
///
/// Reads go through [JsonReader], so a payload written by an older build with a
/// field since renamed raises [JsonFormatError] naming that field, rather than a
/// `TypeError` naming two types. [CatalogCacheStore] turns either into a miss.
///
/// Two deliberate asymmetries with the Audius DTOs, both of which come from the
/// fact that this reads *our own* output rather than a stranger's:
///
///  * Field names are spelled out instead of shortened to save bytes. The whole
///    cache is tens of kilobytes; being able to read a dumped payload while
///    working out why a screen came back wrong is worth more than the
///    difference.
///  * [encodeItem] and friends are functions, not a class per model. A DTO
///    exists to hold a foreign shape still while it is translated; here there is
///    no foreign shape, only two directions of the same map.
library;

import '../../network/json_reader.dart';
import 'catalog_detail.dart';
import 'catalog_item.dart';
import 'catalog_section.dart';
import 'search_results.dart';
import 'track.dart';

/// Identity and the things a row cannot be drawn without are read strictly:
/// missing or empty means the entry is unusable, and an unusable entry should be
/// a miss rather than a blank row.
///
/// Decoration is read leniently -- see [_text]. The same split [AudiusArtwork]
/// makes, and for the same reason.
Map<String, Object?> encodeItem(CatalogItem item) => {
  'id': item.id,
  'title': item.title,
  'subtitle': item.subtitle,
  'coverColor': item.coverColor,
  'coverUrls': item.coverUrls,
};

CatalogItem decodeItem(Map<String, Object?> json, {String at = ''}) => CatalogItem(
  id: json.string('id', at: at),
  title: json.string('title', at: at),
  subtitle: _text(json, 'subtitle'),
  coverColor: json.integer('coverColor', at: at),
  coverUrls: json.stringList('coverUrls', at: at),
);

/// The duration goes out as whole milliseconds. `Duration` is microseconds
/// internally and JSON has one number type, so writing it as a number of
/// anything is a choice: milliseconds because no source of tracks is more
/// precise than seconds, and because a bare integer survives a decoder that
/// hands back `double` for `3.0`.
Map<String, Object?> encodeTrack(Track track) => {
  'id': track.id,
  'title': track.title,
  'artist': track.artist,
  'durationMs': track.duration.inMilliseconds,
  'audioUrl': track.audioUrl,
  'coverUrls': track.coverUrls,
};

Track decodeTrack(Map<String, Object?> json, {String at = ''}) => Track(
  id: json.string('id', at: at),
  title: json.string('title', at: at),
  artist: _text(json, 'artist'),
  duration: Duration(milliseconds: json.integer('durationMs', at: at)),
  // Strict: a track with no audio url is not a track, it is a row that does
  // nothing when tapped.
  audioUrl: json.string('audioUrl', at: at),
  coverUrls: json.stringList('coverUrls', at: at),
);

Map<String, Object?> encodeSection(CatalogSection section) => {
  'title': section.title,
  'items': [for (final item in section.items) encodeItem(item)],
};

CatalogSection decodeSection(Map<String, Object?> json, {String at = ''}) => CatalogSection(
  title: json.string('title', at: at),
  items: [
    for (final (index, item) in json.objectList('items', at: at).indexed)
      decodeItem(item, at: '$at.items[$index]'),
  ],
);

/// Home's rows, wrapped in an object because that is what the store holds: a
/// bare JSON array has nowhere to grow a field, and the envelope around this
/// (see [CatalogCacheStore]) is an object too.
Map<String, Object?> encodeSections(List<CatalogSection> sections) => {
  'sections': [for (final section in sections) encodeSection(section)],
};

List<CatalogSection> decodeSections(Map<String, Object?> json) => [
  for (final (index, section) in json.objectList('sections').indexed)
    decodeSection(section, at: 'sections[$index]'),
];

Map<String, Object?> encodeDetail(CatalogDetail detail) => {
  'item': encodeItem(detail.item),
  'tracks': [for (final track in detail.tracks) encodeTrack(track)],
};

CatalogDetail decodeDetail(Map<String, Object?> json) => CatalogDetail(
  item: decodeItem(json.object('item'), at: 'item'),
  tracks: [
    for (final (index, track) in json.objectList('tracks').indexed)
      decodeTrack(track, at: 'tracks[$index]'),
  ],
);

Map<String, Object?> encodeHit(TrackHit hit) => {
  'track': encodeTrack(hit.track),
  'album': encodeItem(hit.album),
};

TrackHit decodeHit(Map<String, Object?> json, {String at = ''}) => TrackHit(
  track: decodeTrack(json.object('track', at: at), at: '$at.track'),
  album: decodeItem(json.object('album', at: at), at: '$at.album'),
);

/// The id-keyed collections, which is how the two bulk lookups are kept.
///
/// Keyed by id rather than stored as the answer to one question, because the
/// question is unbounded: Home asks for the handful of ids in the play history
/// and Library asks for everything the user has liked, so caching each *call*
/// would mean an entry per distinct set of ids, and two callers would evict each
/// other while asking for overlapping things. Keeping the entities instead makes
/// a later call answerable out of what earlier ones happened to fetch, and both
/// interface methods already promise to drop ids they have nothing for -- so a
/// partial answer is not a compromise, it is the contract.
Map<String, Object?> encodeItemsById(Iterable<CatalogItem> items) => {
  for (final item in items) item.id: encodeItem(item),
};

Map<String, CatalogItem> decodeItemsById(Map<String, Object?> json) => {
  for (final entry in json.entries)
    entry.key: decodeItem(_objectAt(entry.value, entry.key), at: entry.key),
};

/// Keyed by *track* id, not by the stand-in album's -- see [TrackHit]. The two
/// happen to be equal for an Audius upload, which is exactly the kind of
/// coincidence worth not depending on.
Map<String, Object?> encodeHitsById(Iterable<TrackHit> hits) => {
  for (final hit in hits) hit.track.id: encodeHit(hit),
};

Map<String, TrackHit> decodeHitsById(Map<String, Object?> json) => {
  for (final entry in json.entries)
    entry.key: decodeHit(_objectAt(entry.value, entry.key), at: entry.key),
};

/// A string field that is allowed to be empty, and whose absence is not worth
/// rejecting a whole entry over: a subtitle, an artist name.
///
/// [JsonReader.string] treats `""` as missing, which is right for a field read
/// off a stranger's API -- a track titled `""` is not displayable either way.
/// It is wrong here: these two fields are non-nullable in the model and may
/// legitimately hold `""`, so reading them strictly would turn a faithfully
/// stored empty subtitle into a cache miss for the whole entry.
String _text(Map<String, Object?> json, String key) => json.stringOrNull(key) ?? '';

/// A map value that has to be an object, named by its key.
///
/// The id-keyed collections cannot use [JsonReader.object]: their keys are data,
/// so there is no field name to ask for.
Map<String, Object?> _objectAt(Object? value, String key) {
  if (value is Map<String, Object?>) return value;
  throw JsonFormatError(key, 'expected an object, got ${value.runtimeType}');
}
