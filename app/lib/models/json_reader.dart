import 'dart:convert';

/// Strict reader for decoded JSON: every field is type-checked and unknown keys are rejected.
class JsonReader {
  /// Wraps [json]; [what] names the model in error messages.
  JsonReader(Object? json, this.what) : _map = _asMap(json, what);

  /// Name of the model being read, for error messages.
  final String what;
  final Map<String, Object?> _map;
  final Set<String> _used = <String>{};

  static Map<String, Object?> _asMap(Object? json, String what) {
    if (json is Map<String, Object?>) {
      return json;
    }
    if (json is Map<Object?, Object?>) {
      return json.map(
        (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
      );
    }
    throw FormatException('$what: expected an object, got ${json.runtimeType}');
  }

  Never _fail(String key, String expected) => throw FormatException(
    '$what.$key: expected $expected, got ${_map[key].runtimeType}',
  );

  Object? _raw(String key) {
    _used.add(key);
    return _map[key];
  }

  /// The wrapped map, for handing to another parser.
  Map<String, Object?> get rawMap => _map;

  /// Whether [key] is present (and not null).
  bool has(String key) => _map[key] != null;

  /// A required string.
  String string(String key) {
    final Object? v = _raw(key);
    return v is String ? v : _fail(key, 'a string');
  }

  /// An optional string.
  String? optString(String key) {
    final Object? v = _raw(key);
    if (v == null) {
      return null;
    }
    return v is String ? v : _fail(key, 'a string');
  }

  /// A required integer, at least [min].
  int integer(String key, {int min = -1 << 62}) {
    final Object? v = _raw(key);
    if (v is! int) {
      _fail(key, 'an integer');
    }
    if (v < min) {
      throw FormatException('$what.$key: must be >= $min, got $v');
    }
    return v;
  }

  /// An optional integer, at least [min].
  int? optInteger(String key, {int min = -1 << 62}) =>
      has(key) ? integer(key, min: min) : null;

  /// A required number (integer or decimal), at least [min].
  double number(String key, {double min = double.negativeInfinity}) {
    final Object? v = _raw(key);
    if (v is! num) {
      _fail(key, 'a number');
    }
    if (v < min) {
      throw FormatException('$what.$key: must be >= $min, got $v');
    }
    return v.toDouble();
  }

  /// A required boolean.
  bool boolean(String key) {
    final Object? v = _raw(key);
    return v is bool ? v : _fail(key, 'a boolean');
  }

  /// A required string that must be one of [allowed].
  String oneOf(String key, Set<String> allowed) {
    final String v = string(key);
    if (!allowed.contains(v)) {
      throw FormatException(
        '$what.$key: $v is not one of ${allowed.join('|')}',
      );
    }
    return v;
  }

  /// A required list.
  List<Object?> list(String key) {
    final Object? v = _raw(key);
    return v is List<Object?> ? v : _fail(key, 'a list');
  }

  /// A required nested object.
  JsonReader object(String key) => JsonReader(_raw(key), '$what.$key');

  /// An optional free-form map of scalars.
  Map<String, Object> scalarMap(String key) {
    final Object? v = _raw(key);
    if (v == null) {
      return const <String, Object>{};
    }
    final Map<String, Object?> map = _asMap(v, '$what.$key');
    return Map<String, Object>.unmodifiable(<String, Object>{
      for (final MapEntry<String, Object?> e in map.entries)
        e.key: switch (e.value) {
          final String s => s,
          final num n => n,
          final bool b => b,
          _ => throw FormatException('$what.$key.${e.key}: expected a scalar'),
        },
    });
  }

  /// Fails if the object holds a key that no accessor read.
  void done() {
    final Set<String> extra = _map.keys.toSet().difference(_used);
    if (extra.isNotEmpty) {
      throw FormatException('$what: unknown field(s) ${extra.join(', ')}');
    }
  }
}

/// Value equality through the JSON form: simple, and impossible to forget a field.
mixin JsonValue {
  /// The JSON form of this value.
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) =>
      other is JsonValue &&
      other.runtimeType == runtimeType &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
