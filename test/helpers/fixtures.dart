import 'dart:convert';
import 'dart:io';

/// Loads a captured API payload from `test/fixtures/`.
///
/// Real responses, trimmed to a few entries with every field intact -- not JSON
/// written to match what the parser expects, which would only prove the parser
/// agrees with its author. The quirks these caught are documented where they are
/// handled (`access.stream` vs `is_streamable`, three-hour "tracks").
///
/// VM-only: reads through `dart:io`.
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
