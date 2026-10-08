part of 'server_message.dart';

/// What a `pres` packet reports; [wire] is the protocol's `what` value.
enum PresenceEvent {
  online('on'),
  offline('off'),

  /// The user switched to another client.
  userAgent('ua'),

  /// The description changed.
  updated('upd'),
  tags('tags'),
  aux('aux'),
  access('acs'),

  /// The topic was deleted or the user was removed from it.
  gone('gone'),
  terminated('term'),

  /// A new message in a topic the session is not attached to.
  message('msg'),
  read('read'),
  received('recv'),
  deleted('del'),
  unknown('');

  const PresenceEvent(this.wire);

  final String wire;

  static final Map<String, PresenceEvent> _byWire = {
    for (final e in values) e.wire: e,
  };
}

/// A presence or change notification. Best effort and never stored.
final class PresMessage extends ServerMessage {
  const PresMessage({
    required this.topic,
    required this.event,
    this.source,
    this.seq,
    this.userAgent,
    this.lastDeleteId,
    this.deletedRanges = const [],
  });

  factory PresMessage._fromJson(Json json) {
    final r = StrictJson(json);
    final what = r.require<String>('what', 'pres');
    return PresMessage(
      topic: r.require('topic', 'pres'),
      event: PresenceEvent._byWire[what] ?? PresenceEvent.unknown,
      source: r.optional('src', 'pres'),
      seq: r.optional('seq', 'pres'),
      userAgent: r.optional('ua', 'pres'),
      lastDeleteId: r.optional('clear', 'pres'),
      deletedRanges: r.list('delseq', 'pres', SeqRange.fromJson),
    );
  }

  @override
  final String topic;
  final PresenceEvent event;

  /// The topic or user the event is about; on `me` it names the chat.
  final String? source;
  final int? seq;
  final String? userAgent;

  /// On [PresenceEvent.deleted]: the delete ID of the deletion (`clear`).
  final int? lastDeleteId;

  /// On [PresenceEvent.deleted]: the seqs deleted (`delseq`).
  final List<SeqRange> deletedRanges;

  @override
  List<Object?> get props => [
    topic,
    event,
    source,
    seq,
    userAgent,
    lastDeleteId,
    deletedRanges,
  ];
}
