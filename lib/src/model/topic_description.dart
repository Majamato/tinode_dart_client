import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/access_mode.dart';
import 'package:tinode_dart_client/src/model/private_settings.dart';
import 'package:tinode_dart_client/src/model/profile.dart';
import 'package:tinode_dart_client/src/model/subscription.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// A topic's description (`meta.desc`).
final class TopicDescription with ValueObject {
  const TopicDescription({
    this.created,
    this.updated,
    this.lastMessageAt,
    this.defaultAccess,
    this.access,
    this.lastSeq = 0,
    this.read = 0,
    this.received = 0,
    this.lastDeleteId = 0,
    this.public,
    this.private,
    this.seen,
  });

  factory TopicDescription.fromJson(Json json, String path) {
    final r = StrictJson(json);
    return TopicDescription(
      created: r.optionalTime('created', path),
      updated: r.optionalTime('updated', path),
      lastMessageAt: r.optionalTime('touched', path),
      defaultAccess: switch (r.optionalObject('defacs', path)) {
        null => null,
        final d => DefaultAccess.fromJson(d, '$path.defacs'),
      },
      access: switch (r.optionalObject('acs', path)) {
        null => null,
        final a => Access.fromJson(a, '$path.acs'),
      },
      lastSeq: r.optional('seq', path) ?? 0,
      read: r.optional('read', path) ?? 0,
      received: r.optional('recv', path) ?? 0,
      lastDeleteId: r.optional('clear', path) ?? 0,
      public: Profile.tryParse(json['public']),
      private: PrivateSettings.tryParse(json['private']),
      seen: switch (r.optionalObject('seen', path)) {
        null => null,
        final s => LastSeen.fromJson(s, '$path.seen'),
      },
    );
  }

  final DateTime? created;
  final DateTime? updated;
  final DateTime? lastMessageAt;
  final DefaultAccess? defaultAccess;

  /// The current user's access.
  final Access? access;
  final int lastSeq;
  final int read;
  final int received;
  final int lastDeleteId;
  final Profile? public;
  final PrivateSettings? private;

  /// Only present on P2P topics: when the peer was last online.
  final LastSeen? seen;

  @override
  List<Object?> get props => [
    created,
    updated,
    lastMessageAt,
    defaultAccess,
    access,
    lastSeq,
    read,
    received,
    lastDeleteId,
    public,
    private,
    seen,
  ];
}
