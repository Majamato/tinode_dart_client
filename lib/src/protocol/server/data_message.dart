part of 'server_message.dart';

/// A chat message, numbered per topic by [seq].
final class DataMessage extends ServerMessage {
  const DataMessage({
    required this.topic,
    required this.seq,
    required this.time,
    required this.content,
    this.from,
    this.head,
  });

  factory DataMessage._fromJson(Json json) {
    final r = StrictJson(json);
    return DataMessage(
      topic: r.require('topic', 'data'),
      from: r.optional('from', 'data'),
      seq: r.require('seq', 'data'),
      time: r.requireTime('ts', 'data'),
      head: switch (json['head']) {
        final Json head => MessageHead.fromJson(head),
        _ => null,
      },
      content: MessageContent.fromJson(json['content']),
    );
  }

  @override
  final String topic;

  /// Absent for server-generated messages and for channel readers.
  final String? from;
  final int seq;
  final DateTime time;
  final MessageHead? head;
  final MessageContent content;

  @override
  List<Object?> get props => [topic, from, seq, time, head, content];
}
