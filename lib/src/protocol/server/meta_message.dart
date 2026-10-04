part of 'server_message.dart';

/// Topic metadata, sent in reply to `get`, `sub` or `set`.
final class MetaMessage extends ServerMessage {
  const MetaMessage({
    required this.topic,
    required this.time,
    this.id,
    this.description,
    this.subscriptions = const [],
    this.tags = const [],
  });

  factory MetaMessage._fromJson(Json json) {
    final r = StrictJson(json);
    return MetaMessage(
      id: r.optional('id', 'meta'),
      topic: r.require('topic', 'meta'),
      time: r.requireTime('ts', 'meta'),
      description: switch (r.optionalObject('desc', 'meta')) {
        null => null,
        final d => TopicDescription.fromJson(d, 'meta.desc'),
      },
      subscriptions: r.list('sub', 'meta', Subscription.fromJson),
      tags: [
        for (final tag in r.optional<List<Object?>>('tags', 'meta') ?? const [])
          if (tag is String) tag,
      ],
    );
  }

  final String? id;
  @override
  final String topic;
  final DateTime time;
  final TopicDescription? description;
  final List<Subscription> subscriptions;
  final List<String> tags;

  @override
  List<Object?> get props => [
    id,
    topic,
    time,
    description,
    subscriptions,
    tags,
  ];
}
