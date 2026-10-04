import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/access_mode.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// The user's own settings for a topic, read from its `private` field.
///
/// Only that user can read or write them, and all their devices share them.
/// Typed keys follow Tinode's documented convention; anything else the app
/// stores stays in [raw]. Keys with the wrong type are ignored.
final class PrivateSettings with ValueObject {
  const PrivateSettings({
    this.comment,
    this.archived = false,
    this.accepted,
    this.pinnedTopics = const [],
    this.raw = const {},
  });

  factory PrivateSettings.fromJson(Json json) {
    final j = LooseJson(json);
    return PrivateSettings(
      comment: j.get('comment'),
      archived: j.get('arch') ?? false,
      accepted: switch (j.get<String>('accepted')) {
        null => null,
        final letters => AccessMode.parse(letters),
      },
      pinnedTopics: [
        for (final topic in j.get<List<Object?>>('tpins') ?? const <Object?>[])
          if (topic is String) topic,
      ],
      raw: json,
    );
  }

  /// Null unless [value] is an object.
  static PrivateSettings? tryParse(Object? value) => switch (value) {
    final Json json => PrivateSettings.fromJson(json),
    _ => null,
  };

  /// The user's note about the topic or peer.
  final String? comment;
  final bool archived;

  /// The access the topic granted that the user has accepted.
  final AccessMode? accepted;

  /// Topics pinned to the top of the chat list; only set on `me`.
  final List<String> pinnedTopics;
  final Json raw;

  @override
  List<Object?> get props => [comment, archived, accepted, pinnedTopics, raw];
}
