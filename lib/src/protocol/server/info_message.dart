part of 'server_message.dart';

/// What an `info` packet reports; [wire] is the protocol's `what` value.
enum InfoEvent {
  typing('kp'),
  received('recv'),
  read('read'),
  call('call'),
  unknown('');

  const InfoEvent(this.wire);

  final String wire;

  static final Map<String, InfoEvent> _byWire = {
    for (final e in values) e.wire: e,
  };
}

/// A `note` from another user, forwarded by the server, or a call update
/// from the server itself.
final class InfoMessage extends ServerMessage {
  const InfoMessage({
    required this.topic,
    required this.event,
    this.from,
    this.source,
    this.seq,
    this.callEvent,
    this.payload,
  });

  factory InfoMessage._fromJson(Json json) {
    final r = StrictJson(json);
    final what = r.require<String>('what', 'info');
    final event = InfoEvent._byWire[what] ?? InfoEvent.unknown;

    return InfoMessage(
      topic: r.require('topic', 'info'),
      event: event,
      from: r.optional('from', 'info'),
      source: r.optional('src', 'info'),
      seq: r.optional('seq', 'info'),
      callEvent: event == InfoEvent.call
          ? CallEvent.of(r.optional<String>('event', 'info') ?? '')
          : null,
      payload: switch (json['payload']) {
        final Json payload => payload,
        _ => null,
      },
    );
  }

  @override
  final String topic;
  final InfoEvent event;

  /// Who sent the note. The server leaves it out when it ends a call, and
  /// sends `""` on `me` when it ended the call itself.
  final String? from;

  /// On `me`: the chat the note is about.
  final String? source;

  /// For [InfoEvent.read] and [InfoEvent.received]: up to which message.
  /// For [InfoEvent.call]: the call, i.e. the seq of the message that
  /// started it.
  final int? seq;

  /// The step of the call, for [InfoEvent.call] only.
  final CallEvent? callEvent;

  /// Data the peer attached to [callEvent], passed on as sent.
  final Json? payload;

  /// The SDP of a [CallEvent.offer] or [CallEvent.answer].
  CallDescription? get description => CallDescription.tryParse(payload);

  /// The candidate of a [CallEvent.iceCandidate].
  IceCandidate? get candidate => IceCandidate.tryParse(payload);

  @override
  List<Object?> get props => [
    topic,
    event,
    from,
    source,
    seq,
    callEvent,
    payload,
  ];
}
