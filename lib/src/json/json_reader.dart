import 'package:tinode_dart_client/src/errors.dart';

/// A decoded JSON object, as produced by `jsonDecode`.
typedef Json = Map<String, Object?>;

/// Strict reads for protocol-defined fields; a mismatch throws
/// [MalformedPacketException] naming the offending path.
extension type const StrictJson(Json json) {
  T require<T extends Object>(String key, String path) => switch (json[key]) {
    final T value => value,
    final other => throw MalformedPacketException('$path.$key', other),
  };

  T? optional<T extends Object>(String key, String path) => switch (json[key]) {
    null => null,
    final T value => value,
    final other => throw MalformedPacketException('$path.$key', other),
  };

  DateTime requireTime(String key, String path) =>
      _time(require<String>(key, path), '$path.$key');

  DateTime? optionalTime(String key, String path) =>
      switch (optional<String>(key, path)) {
        null => null,
        final s => _time(s, '$path.$key'),
      };

  Json? optionalObject(String key, String path) => optional<Json>(key, path);

  /// Parses each element with [parse]; a non-object element is malformed.
  List<T> list<T>(String key, String path, T Function(Json, String) parse) {
    final raw = optional<List<Object?>>(key, path);
    if (raw == null) return const [];
    return [
      for (var i = 0; i < raw.length; i++)
        switch (raw[i]) {
          final Json item => parse(item, '$path.$key[$i]'),
          final other => throw MalformedPacketException(
            '$path.$key[$i]',
            other,
          ),
        },
    ];
  }

  static DateTime _time(String value, String path) =>
      DateTime.tryParse(value) ?? (throw MalformedPacketException(path, value));
}

/// Times as the server writes them.
extension WireTime on DateTime {
  /// RFC 3339 in UTC.
  String get wire => toUtc().toIso8601String();
}

/// Lenient reads for app-defined blobs: wrong types become `null`.
extension type const LooseJson(Json json) {
  T? get<T extends Object>(String key) => switch (json[key]) {
    final T value => value,
    _ => null,
  };

  DateTime? time(String key) => switch (json[key]) {
    final String s => DateTime.tryParse(s),
    _ => null,
  };
}
