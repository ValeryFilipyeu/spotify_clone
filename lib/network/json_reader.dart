/// Raised when a decoded payload is not the shape the caller needs: a missing
/// field, a null where a value is required, or a value of the wrong type.
///
/// Deliberately not an [ApiFailure]: the code that reads a field knows *what*
/// was wrong but not *which request* produced it, and a failure with no url is
/// a bad log line. The repository that made the call catches this and re-throws
/// it as a `MalformedResponse` carrying its uri.
class JsonFormatError implements Exception {
  const JsonFormatError(this.path, this.reason);

  /// Where in the payload, e.g. `data[2].user.name`. Worth the small effort of
  /// threading through: "expected a string" on its own is not a bug report.
  final String path;

  final String reason;

  @override
  String toString() => 'JsonFormatError at $path: $reason';
}

/// Typed reads over a decoded JSON object.
///
/// The alternative -- casting inline at every field, `json['user']['name'] as
/// String` -- fails with a `TypeError` naming only the types involved, so a
/// backend that renames one field produces "String is not a subtype of Null"
/// and no clue which field. These raise [JsonFormatError] naming the path
/// instead, and cost one method call to do it.
extension JsonReader on Map<String, Object?> {
  /// A required nested object.
  Map<String, Object?> object(String key, {String at = ''}) {
    final value = this[key];
    if (value is! Map<String, Object?>) {
      throw JsonFormatError(_path(at, key), 'expected an object, got ${value.runtimeType}');
    }
    return value;
  }

  /// A nested object that is allowed to be absent or null -- `artwork` on a
  /// track with none, for instance.
  Map<String, Object?>? objectOrNull(String key) {
    final value = this[key];
    return value is Map<String, Object?> ? value : null;
  }

  /// A required list of objects. Anything in the list that is not an object is
  /// an error rather than being skipped: a half-readable list is a backend
  /// change worth hearing about, not something to paper over.
  List<Map<String, Object?>> objectList(String key, {String at = ''}) {
    final value = this[key];
    if (value is! List) {
      throw JsonFormatError(_path(at, key), 'expected a list, got ${value.runtimeType}');
    }
    return [
      for (final (index, element) in value.indexed)
        if (element is Map<String, Object?>)
          element
        else
          throw JsonFormatError('${_path(at, key)}[$index]', 'expected an object, got ${element.runtimeType}'),
    ];
  }

  /// A required, non-empty string. Empty counts as missing: a track whose title
  /// is `""` is no more displayable than one with no title field.
  String string(String key, {String at = ''}) {
    final value = this[key];
    if (value is! String || value.isEmpty) {
      throw JsonFormatError(_path(at, key), 'expected a non-empty string, got ${_describe(value)}');
    }
    return value;
  }

  /// A string, or null if absent, null or empty.
  String? stringOrNull(String key) {
    final value = this[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// A required integer. Reads through `num` because a JSON number may decode
  /// as a double even when the API only ever sends whole ones.
  int integer(String key, {String at = ''}) {
    final value = this[key];
    if (value is! num) {
      throw JsonFormatError(_path(at, key), 'expected a number, got ${_describe(value)}');
    }
    return value.toInt();
  }

  /// A boolean, falling back to [orElse] when absent or null -- for the flags a
  /// payload only includes when they are interesting.
  bool boolean(String key, {bool orElse = false}) {
    final value = this[key];
    return value is bool ? value : orElse;
  }

  static String _path(String at, String key) => at.isEmpty ? key : '$at.$key';

  static String _describe(Object? value) => value == null ? 'null' : '${value.runtimeType}';
}
