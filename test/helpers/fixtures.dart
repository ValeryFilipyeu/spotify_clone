import 'dart:convert';
import 'dart:io';

/// Loads a captured API payload from `test/fixtures/`.
///
/// These are real responses, recorded off the live API and trimmed to a few
/// entries with every field left intact -- not JSON written by hand to match
/// what the parser expects. That difference is the whole value of them: a
/// hand-written fixture only ever proves the parser agrees with its author,
/// and it cannot contain the things a real payload does. The quirks these
/// caught are documented where they are handled (`access.stream` versus
/// `is_streamable`, per-track artwork hosts, three-hour "tracks").
///
/// Reads through `dart:io`, so these tests are VM-only. Nothing here needs to
/// run in a browser.
Map<String, Object?> fixture(String path) {
  final file = File('test/fixtures/$path.json');
  if (!file.existsSync()) {
    throw ArgumentError('No fixture at ${file.path}. Fixtures live in test/fixtures/.');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// The `data` array of a captured payload, which is how every Audius endpoint
/// wraps its result.
List<Map<String, Object?>> fixtureData(String path) =>
    (fixture(path)['data']! as List).cast<Map<String, Object?>>();
