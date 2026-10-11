import 'dart:convert';

import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/access_mode.dart';
import 'package:tinode_dart_client/src/model/call.dart';
import 'package:tinode_dart_client/src/model/drafty.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// A push notification from the server: the data of a message from the
/// push service, e.g. `RemoteMessage.data` in Firebase Cloud Messaging.
/// It needs no client, so a background handler can read it.
///
/// The push service sends every value as a string; numbers and flags are
/// read from either form, and a malformed one reads as missing.
sealed class TinodePush with ValueObject {
  const TinodePush({
    required this.topic,
    this.from,
    this.sentAt,
    this.silent = false,
    this.raw = const {},
  });

  /// Null when [data] isn't a push from Tinode, e.g. one of the app's own,
  /// or of a kind this version doesn't know.
  static TinodePush? tryParse(Map<String, Object?> data) {
    final topic = _string(data, 'topic');
    if (topic == null || topic.isEmpty) return null;
    final from = _string(data, 'xfrom');
    final sentAt = switch (_string(data, 'ts')) {
      null => null,
      final ts => DateTime.tryParse(ts),
    };
    final silent = _flag(data, 'silent');
    return switch (_string(data, 'what')) {
      'msg' => MessagePush(
        topic: topic,
        from: from,
        sentAt: sentAt,
        silent: silent,
        seq: _int(data, 'seq'),
        mimeType: _string(data, 'mime'),
        text: _string(data, 'content'),
        preview: _drafty(data['rc']),
        callState: switch (_string(data, 'webrtc')) {
          null || '' => null,
          final s => CallState.of(s),
        },
        audioOnly: _flag(data, 'aonly'),
        replaces: _string(data, 'replace'),
        raw: data,
      ),
      'sub' => SubscriptionPush(
        topic: topic,
        from: from,
        sentAt: sentAt,
        silent: silent,
        want: _mode(data, 'modeWant'),
        given: _mode(data, 'modeGiven'),
        raw: data,
      ),
      'read' => ReadPush(
        topic: topic,
        from: from,
        sentAt: sentAt,
        silent: silent,
        seq: _int(data, 'seq'),
        raw: data,
      ),
      _ => null,
    };
  }

  /// The chat, as the recipient names it: for a 1:1 chat, the other
  /// user's ID.
  final String topic;

  /// The user who caused the push (`xfrom`), e.g. the sender.
  final String? from;
  final DateTime? sentAt;

  /// Nothing to show the user: they saw it already in the app, or it
  /// only updates state (a read, a call's progress).
  final bool silent;

  /// The data as received.
  final Map<String, Object?> raw;

  /// The data as received, which [tryParse] reads back.
  Map<String, Object?> toJson() => raw;
}

/// A new message (`what: msg`), or a change to a call message.
final class MessagePush extends TinodePush {
  const MessagePush({
    required super.topic,
    super.from,
    super.sentAt,
    super.silent,
    this.seq,
    this.mimeType,
    this.text,
    this.preview,
    this.callState,
    this.audioOnly = false,
    this.replaces,
    super.raw,
  });

  final int? seq;
  final String? mimeType;

  /// The start of the message as plain text, cut to 128 characters and
  /// `…`.
  final String? text;

  /// The start of the message as Drafty, for servers that send it.
  final Drafty? preview;

  /// Set when the message is a call: [CallState.started] for one that
  /// rings, later states when it ends.
  final CallState? callState;

  /// The call has no video.
  final bool audioOnly;

  /// `:<seq>` of the message this one edits.
  final String? replaces;

  @override
  List<Object?> get props => [
    topic,
    from,
    sentAt,
    silent,
    seq,
    mimeType,
    text,
    preview,
    callState,
    audioOnly,
    replaces,
    raw,
  ];
}

/// The user was added to a chat, or their access to it changed
/// (`what: sub`).
final class SubscriptionPush extends TinodePush {
  const SubscriptionPush({
    required super.topic,
    super.from,
    super.sentAt,
    super.silent,
    this.want,
    this.given,
    super.raw,
  });

  final AccessMode? want;
  final AccessMode? given;

  @override
  List<Object?> get props => [topic, from, sentAt, silent, want, given, raw];
}

/// The user read the chat up to [seq] on another device (`what: read`):
/// notifications for it can go. Always [silent].
final class ReadPush extends TinodePush {
  const ReadPush({
    required super.topic,
    super.from,
    super.sentAt,
    super.silent,
    this.seq,
    super.raw,
  });

  final int? seq;

  @override
  List<Object?> get props => [topic, from, sentAt, silent, seq, raw];
}

String? _string(Map<String, Object?> data, String key) => switch (data[key]) {
  final String s => s,
  final num n => '$n',
  final bool b => '$b',
  _ => null,
};

int? _int(Map<String, Object?> data, String key) => switch (data[key]) {
  final int n => n,
  final String s => int.tryParse(s),
  _ => null,
};

bool _flag(Map<String, Object?> data, String key) => switch (data[key]) {
  final bool b => b,
  final String s => s == 'true',
  _ => false,
};

AccessMode? _mode(Map<String, Object?> data, String key) =>
    switch (_string(data, key)) {
      null => null,
      final letters => AccessMode.parse(letters),
    };

/// The Drafty preview (`rc`), sent as JSON text.
Drafty? _drafty(Object? rc) {
  final Object? decoded;
  try {
    decoded = rc is String ? jsonDecode(rc) : rc;
  } on FormatException {
    return null;
  }
  return switch (decoded) {
    final Json json => Drafty.fromJson(json),
    // A plain string is valid Drafty too.
    final String text => Drafty(text: text),
    _ => null,
  };
}
