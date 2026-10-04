import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/access_mode.dart';
import 'package:tinode_dart_client/src/model/private_settings.dart';
import 'package:tinode_dart_client/src/model/profile.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// One entry of `meta.sub`. Queried on `me` it is a chat in the user's
/// chat list ([topic] set); on other topics it is a member ([userId] set).
final class Subscription with ValueObject {
  const Subscription({
    this.topic,
    this.userId,
    this.updated,
    this.lastMessageAt,
    this.access,
    this.online = false,
    this.lastSeq = 0,
    this.read = 0,
    this.received = 0,
    this.lastDeleteId = 0,
    this.public,
    this.private,
    this.seen,
  });

  factory Subscription.fromJson(Json json, String path) {
    final r = StrictJson(json);
    return Subscription(
      topic: r.optional('topic', path),
      userId: r.optional('user', path),
      updated: r.optionalTime('updated', path),
      lastMessageAt: r.optionalTime('touched', path),
      access: switch (r.optionalObject('acs', path)) {
        null => null,
        final a => Access.fromJson(a, '$path.acs'),
      },
      online: r.optional('online', path) ?? false,
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

  final String? topic;
  final String? userId;
  final DateTime? updated;
  final DateTime? lastMessageAt;
  final Access? access;
  final bool online;
  final int lastSeq;

  /// Highest seq this user has read / received.
  final int read;
  final int received;
  final int lastDeleteId;
  final Profile? public;
  final PrivateSettings? private;

  /// Only present for P2P peers.
  final LastSeen? seen;

  int get unread => lastSeq > read ? lastSeq - read : 0;

  @override
  List<Object?> get props => [
    topic,
    userId,
    updated,
    lastMessageAt,
    access,
    online,
    lastSeq,
    read,
    received,
    lastDeleteId,
    public,
    private,
    seen,
  ];
}

/// When a P2P peer was last online and with which client.
final class LastSeen with ValueObject {
  const LastSeen({this.when, this.userAgent});

  factory LastSeen.fromJson(Json json, String path) {
    final r = StrictJson(json);
    return LastSeen(
      when: r.optionalTime('when', path),
      userAgent: r.optional('ua', path),
    );
  }

  final DateTime? when;
  final String? userAgent;

  @override
  List<Object?> get props => [when, userAgent];
}
