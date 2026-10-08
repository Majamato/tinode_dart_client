import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/access_mode.dart';
import 'package:tinode_dart_client/src/model/profile.dart';
import 'package:tinode_dart_client/src/model/topic_kind.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// A user or group that `fnd` found: one entry of `meta.sub` on `fnd`.
///
/// A user comes back under its user ID (`usr…`), which is also the name
/// of the 1:1 chat with them; a group under its `grp…` name.
final class FoundTopic with ValueObject {
  const FoundTopic({
    required this.topic,
    this.updated,
    this.defaultMode,
    this.public,
    this.matchedTags = const [],
    this.memberCount,
  });

  factory FoundTopic.fromJson(Json json, String path) {
    final r = StrictJson(json);
    return FoundTopic(
      // Tinode's own clients fall back to `user`, so accept it too.
      topic:
          r.optional('topic', path) ??
          r.optional('user', path) ??
          (throw MalformedPacketException('$path.topic', null)),
      updated: r.optionalTime('updated', path),
      defaultMode: switch (r.optionalObject('acs', path)) {
        null => null,
        final acs => switch (StrictJson(acs).optional<String>('mode', path)) {
          null => null,
          final letters => AccessMode.parse(letters),
        },
      },
      public: Profile.tryParse(json['public']),
      matchedTags: [
        for (final tag
            in r.optional<List<Object?>>('private', path) ?? const [])
          if (tag is String) tag,
      ],
      memberCount: r.optional('subcnt', path),
    );
  }

  /// `usr…` for a user, `grp…` or `chn…` for a group or channel.
  final String topic;
  final DateTime? updated;

  /// The access a new subscriber would get (`acs.mode`).
  final AccessMode? defaultMode;
  final Profile? public;

  /// The tags of the query this result matched (`private` on the wire).
  final List<String> matchedTags;

  /// Members of a group; null for users.
  final int? memberCount;

  TopicKind get kind => TopicKind.of(topic);

  /// The wire form, which [FoundTopic.fromJson] reads back.
  Json toJson() => {
    'topic': topic,
    'updated': ?updated?.wire,
    if (defaultMode case final mode?) 'acs': {'mode': '$mode'},
    'public': ?public?.toJson(),
    if (matchedTags.isNotEmpty) 'private': matchedTags,
    'subcnt': ?memberCount,
  };

  @override
  List<Object?> get props => [
    topic,
    updated,
    defaultMode,
    public,
    matchedTags,
    memberCount,
  ];
}
