import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// Tinode's rich-text format: plain [text] plus [spans] over it, some of
/// which point into [entities] (links, mentions, images, files).
final class Drafty with ValueObject {
  const Drafty({
    required this.text,
    this.spans = const [],
    this.entities = const [],
  });

  /// Malformed spans and entities are dropped instead of failing the message.
  factory Drafty.fromJson(Json json) {
    final j = LooseJson(json);
    return Drafty(
      text: j.get('txt') ?? '',
      spans: [
        for (final item in j.get<List<Object?>>('fmt') ?? const <Object?>[])
          if (item case final Json span) Span.fromJson(span),
      ],
      entities: [
        for (final item in j.get<List<Object?>>('ent') ?? const <Object?>[])
          if (item case final Json entity) ?Entity._tryParse(entity),
      ],
    );
  }

  final String text;
  final List<Span> spans;
  final List<Entity> entities;

  Json toJson() => {
    'txt': text,
    if (spans.isNotEmpty) 'fmt': [for (final s in spans) s.toJson()],
    if (entities.isNotEmpty) 'ent': [for (final e in entities) e.toJson()],
  };

  @override
  List<Object?> get props => [text, spans, entities];
}

/// [length] characters starting [at], given an inline [style] (`ST`, `EM`,
/// `CO`…) or linked to the entity at [entityIndex].
final class Span with ValueObject {
  const Span({
    required this.at,
    required this.length,
    this.style,
    this.entityIndex,
  });

  /// Zero values are omitted on the wire, so a missing `at`, `len`
  /// or (for entity spans) `key` means 0.
  factory Span.fromJson(Json json) {
    final j = LooseJson(json);
    final style = j.get<String>('tp');
    return Span(
      at: j.get('at') ?? 0,
      length: j.get('len') ?? 0,
      style: style,
      entityIndex: style == null ? j.get('key') ?? 0 : null,
    );
  }

  final int at;
  final int length;
  final String? style;
  final int? entityIndex;

  Json toJson() => {
    if (at != 0) 'at': at,
    if (length != 0) 'len': length,
    'tp': ?style,
    if (style == null && entityIndex != null && entityIndex != 0)
      'key': entityIndex,
  };

  @override
  List<Object?> get props => [at, length, style, entityIndex];
}

/// A link, mention, image, file… of [type] (`LN`, `MN`, `IM`, `EX`…),
/// with type-specific [data].
final class Entity with ValueObject {
  const Entity({required this.type, this.data = const {}});

  final String type;
  final Json data;

  static Entity? _tryParse(Json json) {
    final j = LooseJson(json);
    final type = j.get<String>('tp');
    if (type == null) return null;
    return Entity(type: type, data: j.get('data') ?? const {});
  }

  Json toJson() => {'tp': type, if (data.isNotEmpty) 'data': data};

  @override
  List<Object?> get props => [type, data];
}
