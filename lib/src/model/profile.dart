import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// The public profile of a user or topic, read from its `public` field.
///
/// Tinode's docs call this format **theCard** (a play on vCard 3.0, which it
/// mirrors). The spec also defines `n`, `org`, `comm` and `bday`; those, and
/// any custom `x-…` keys, are not typed here but stay available in [raw].
/// Parsing is lenient because the server never checks this field's shape.
final class Profile with ValueObject {
  const Profile({this.name, this.note, this.photo, this.raw = const {}});

  factory Profile.fromJson(Json json) {
    final j = LooseJson(json);
    return Profile(
      name: j.get('fn'),
      note: j.get('note'),
      photo: switch (j.get<Json>('photo')) {
        null => null,
        final photo => ProfilePhoto.fromJson(photo),
      },
      raw: json,
    );
  }

  /// Null unless [value] is an object; `fnd` puts a query string there.
  static Profile? tryParse(Object? value) => switch (value) {
    final Json json => Profile.fromJson(json),
    _ => null,
  };

  /// Display name; `fn` (formatted name) on the wire.
  final String? name;
  final String? note;
  final ProfilePhoto? photo;
  final Json raw;

  /// The wire form; keys in [raw] win over the typed fields.
  Json toJson() => {
    'fn': ?name,
    'note': ?note,
    'photo': ?photo?.toJson(),
    ...raw,
  };

  @override
  List<Object?> get props => [name, note, photo, raw];
}

/// An avatar: either inline base64 [data] or a [ref] to an uploaded file.
final class ProfilePhoto with ValueObject {
  const ProfilePhoto({this.type, this.data, this.ref});

  factory ProfilePhoto.fromJson(Json json) {
    final j = LooseJson(json);
    return ProfilePhoto(
      type: j.get('type'),
      data: j.get('data'),
      ref: j.get('ref'),
    );
  }

  /// Image subtype such as `jpg` or `png`.
  final String? type;
  final String? data;

  /// Relative refs resolve against the server's `/v0/file/s/`.
  final String? ref;

  Json toJson() => {'type': ?type, 'data': ?data, 'ref': ?ref};

  @override
  List<Object?> get props => [type, data, ref];
}
