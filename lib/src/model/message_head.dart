import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/call.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// Message headers (`head`). Common keys are typed; [raw] keeps the rest.
final class MessageHead with ValueObject {
  const MessageHead({
    this.mime,
    this.replaces,
    this.replyTo,
    this.callState,
    this.callDuration,
    this.audioOnly = false,
    this.raw = const {},
  });

  factory MessageHead.fromJson(Json json) {
    final j = LooseJson(json);
    final duration = j.get<int>('webrtc-duration');

    return MessageHead(
      mime: j.get('mime'),
      replaces: j.get('replace'),
      replyTo: j.get('reply'),
      callState: switch (j.get<String>('webrtc')) {
        null => null,
        final s => CallState.of(s),
      },
      callDuration: duration == null ? null : Duration(milliseconds: duration),
      audioOnly: j.get('aonly') ?? false,
      raw: json,
    );
  }

  static const draftyMime = 'text/x-drafty';

  final String? mime;

  /// `:<seq>` of the message this one edits.
  final String? replaces;

  /// `<topic>:<seq>` of the message this one replies to.
  final String? replyTo;

  /// Set on call messages and on the server's updates to them.
  final CallState? callState;

  /// How long a [CallState.finished] call lasted.
  final Duration? callDuration;

  /// The call has no video. Only the message that started the call says so;
  /// the server's updates to it leave this out.
  final bool audioOnly;
  final Json raw;

  /// The seq in [replaces], or `null` when there is none or it is malformed.
  int? get replacesSeq => switch (replaces) {
    final r? when r.startsWith(':') => int.tryParse(r.substring(1)),
    _ => null,
  };

  @override
  List<Object?> get props => [
    mime,
    replaces,
    replyTo,
    callState,
    callDuration,
    audioOnly,
    raw,
  ];
}
