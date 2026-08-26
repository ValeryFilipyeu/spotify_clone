/// A decoded payload is not the shape the caller needs.
///
/// Not an [ApiFailure]: whoever reads a field knows *what* was wrong but not
/// which request produced it. The repository re-throws this as a
/// `MalformedResponse` carrying the uri.
class JsonFormatError implements Exception {
  const JsonFormatError(this.path, this.reason);

  /// Where in the payload, e.g. `data[2].user.name` -- "expected a string" on
  /// its own is not a bug report.
  final String path;

  final String reason;

  @override
  String toString() => 'JsonFormatError at $path: $reason';
}

/// Typed reads over a decoded JSON object.
///
/// Casting inline fails with "String is not a subtype of Null" and no clue which
/// field. These raise [JsonFormatError] naming the path.
extension JsonReader on Map<String, Object?> {
  /// A required nested object.
  Map<String, Object?> object(String key, {String at = ''}) {
    final value = this[key];
    if (value is! Map<String, Object?>) {
      throw JsonFormatError(_path(at, key), 'expected an object, got ${value.runtimeType}');
    }
    return value;
  }

  /// A nested object allowed to be absent or null, like `artwork`.
  Map<String, Object?>? objectOrNull(String key) {
    final value = this[key];
    return value is Map<String, Object?> ? value : null;
  }

  /// A required list of objects. A non-object element is an error, not a skip:
  /// half a list is a backend change worth hearing about.
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
          throw JsonFormatError(
            '${_path(at, key)}[$index]',
            'expected an object, got ${element.runtimeType}',
          ),
    ];
  }

  /// A required, non-empty string -- `""` is no more displayable than absent.
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

  /// A list of strings, absent or null being empty -- for fields that appear
  /// only when populated. A non-string element is an error, as in [objectList].
  List<String> stringList(String key, {String at = ''}) {
    final value = this[key];
    if (value == null) return const [];
    if (value is! List) {
      throw JsonFormatError(_path(at, key), 'expected a list, got ${value.runtimeType}');
    }
    return [
      for (final (index, element) in value.indexed)
        if (element is String)
          element
        else
          throw JsonFormatError(
            '${_path(at, key)}[$index]',
            'expected a string, got ${_describe(element)}',
          ),
    ];
  }

  /// Read through `num`: JSON may decode a whole number as a double.
  int integer(String key, {String at = ''}) {
    final value = this[key];
    if (value is! num) {
      throw JsonFormatError(_path(at, key), 'expected a number, got ${_describe(value)}');
    }
    return value.toInt();
  }

  /// A boolean, [orElse] when absent or null.
  bool boolean(String key, {bool orElse = false}) {
    final value = this[key];
    return value is bool ? value : orElse;
  }

  static String _path(String at, String key) => at.isEmpty ? key : '$at.$key';

  static String _describe(Object? value) => value == null ? 'null' : '${value.runtimeType}';
}
