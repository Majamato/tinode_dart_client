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

/// A `note` from another user, forwarded by the server.
final class InfoMessage extends ServerMessage {
  const InfoMessage({
    required this.topic,
    required this.from,
    required this.event,
    this.seq,
  });

  factory InfoMessage._fromJson(Json json) {
    final r = StrictJson(json);
    final what = r.require<String>('what', 'info');
    return InfoMessage(
      topic: r.require('topic', 'info'),
      from: r.require('from', 'info'),
      event: InfoEvent._byWire[what] ?? InfoEvent.unknown,
      seq: r.optional('seq', 'info'),
    );
  }

  @override
  final String topic;
  final String from;
  final InfoEvent event;

  /// For [InfoEvent.read] and [InfoEvent.received]: up to which message.
  final int? seq;

  @override
  List<Object?> get props => [topic, from, event, seq];
}
