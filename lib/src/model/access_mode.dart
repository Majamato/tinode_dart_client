import 'package:meta/meta.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

enum Permission {
  join('J'),
  read('R'),
  write('W'),
  presence('P'),
  approve('A'),
  share('S'),
  delete('D'),
  owner('O');

  const Permission(this.letter);

  final String letter;
}

/// A set of [Permission]s, written by the server as letters (`JRWPS`).
/// `N` means explicitly none and maps to the empty set.
@immutable
final class AccessMode {
  factory AccessMode(Iterable<Permission> permissions) =>
      AccessMode._(permissions.fold(0, (bits, p) => bits | 1 << p.index));

  const AccessMode._(this._bits);

  /// Unknown letters are ignored so newer servers stay readable.
  factory AccessMode.parse(String letters) {
    var bits = 0;
    for (final p in Permission.values) {
      if (letters.contains(p.letter)) bits |= 1 << p.index;
    }
    return AccessMode._(bits);
  }

  static const none = AccessMode._(0);

  final int _bits;

  bool has(Permission p) => _bits & 1 << p.index != 0;

  Set<Permission> get permissions => {
    for (final p in Permission.values)
      if (has(p)) p,
  };

  AccessMode intersect(AccessMode other) => AccessMode._(_bits & other._bits);

  @override
  bool operator ==(Object other) => other is AccessMode && other._bits == _bits;

  @override
  int get hashCode => _bits.hashCode;

  @override
  String toString() =>
      _bits == 0 ? 'N' : permissions.map((p) => p.letter).join();
}

/// A user's access to a topic: what they asked for ([want]), what the
/// topic granted ([given]) and what is in effect ([mode]). Wire name: `acs`.
final class Access with ValueObject {
  const Access({required this.want, required this.given, required this.mode});

  factory Access.fromJson(Json json, String path) {
    final r = StrictJson(json);
    AccessMode read(String key) =>
        AccessMode.parse(r.optional(key, path) ?? 'N');
    return Access(want: read('want'), given: read('given'), mode: read('mode'));
  }

  final AccessMode want;
  final AccessMode given;
  final AccessMode mode;

  @override
  List<Object?> get props => [want, given, mode];
}

/// Access new subscribers get: logged-in ([auth]) and anonymous ([anon])
/// users. Wire name: `defacs`.
final class DefaultAccess with ValueObject {
  const DefaultAccess({required this.auth, required this.anon});

  factory DefaultAccess.fromJson(Json json, String path) {
    final r = StrictJson(json);
    return DefaultAccess(
      auth: AccessMode.parse(r.optional('auth', path) ?? 'N'),
      anon: AccessMode.parse(r.optional('anon', path) ?? 'N'),
    );
  }

  final AccessMode auth;
  final AccessMode anon;

  @override
  List<Object?> get props => [auth, anon];
}
