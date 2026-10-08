part of 'server_message.dart';

/// Topic metadata, sent in reply to `get`, `sub` or `set`.
final class MetaMessage extends ServerMessage {
  const MetaMessage({
    required this.topic,
    required this.time,
    this.id,
    this.description,
    this.subscriptions = const [],
    this.found = const [],
    this.tags = const [],
    this.deleteLog,
  });

  factory MetaMessage._fromJson(Json json) {
    final r = StrictJson(json);
    final topic = r.require<String>('topic', 'meta');
    // On `fnd`, `sub` holds search results, not subscriptions.
    final isSearch = TopicKind.of(topic) == TopicKind.search;

    return MetaMessage(
      id: r.optional('id', 'meta'),
      topic: topic,
      time: r.requireTime('ts', 'meta'),
      description: switch (r.optionalObject('desc', 'meta')) {
        null => null,
        final d => TopicDescription.fromJson(d, 'meta.desc'),
      },
      subscriptions: isSearch
          ? const []
          : r.list('sub', 'meta', Subscription.fromJson),
      found: isSearch ? r.list('sub', 'meta', FoundTopic.fromJson) : const [],
      tags: [
        for (final tag in r.optional<List<Object?>>('tags', 'meta') ?? const [])
          if (tag is String) tag,
      ],
      deleteLog: switch (r.optionalObject('del', 'meta')) {
        null => null,
        final d => DeleteLog.fromJson(d, 'meta.del'),
      },
    );
  }

  final String? id;
  @override
  final String topic;
  final DateTime time;
  final TopicDescription? description;
  final List<Subscription> subscriptions;

  /// The results of a search, in reply to `get what=sub` on `fnd`.
  final List<FoundTopic> found;
  final List<String> tags;

  /// Deleted messages, in reply to `get what=del`.
  final DeleteLog? deleteLog;

  @override
  List<Object?> get props => [
    id,
    topic,
    time,
    description,
    subscriptions,
    found,
    tags,
    deleteLog,
  ];
}
