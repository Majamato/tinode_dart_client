import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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

  /// The content of a call message: one space marked as a `VC` entity.
  /// Clients draw the call's state from the message head, not from this.
  factory Drafty.videoCall({bool audioOnly = false}) => Drafty(
    text: ' ',
    spans: const [Span(at: 0, length: 1, entityIndex: 0)],
    entities: [
      Entity(type: Entity.videoCallType, data: {if (audioOnly) 'aonly': true}),
    ],
  );

  /// An image with an optional [caption] under it, as TinodeWeb sends it:
  /// a space for the image, then a line break and the caption.
  factory Drafty.image(DraftyImage image, {String caption = ''}) => Drafty(
    text: caption.isEmpty ? ' ' : '  $caption',
    spans: [
      const Span(at: 0, length: 1, entityIndex: 0),
      if (caption.isNotEmpty)
        const Span(at: 1, length: 1, style: Span.lineBreakStyle),
    ],
    entities: [Entity(type: Entity.imageType, data: image.toData())],
  );

  /// A file attached below an optional [caption], shown as a download
  /// rather than inline: its span sits at `-1`.
  factory Drafty.file(DraftyFile file, {String caption = ''}) => Drafty(
    text: caption,
    spans: const [Span(at: -1, length: 0, entityIndex: 0)],
    entities: [Entity(type: Entity.fileType, data: file.toData())],
  );

  final String text;
  final List<Span> spans;
  final List<Entity> entities;

  /// The images, in the order of their spans.
  List<DraftyImage> get images => [
    for (final entity in _linkedEntities) ?entity.asImage,
  ];

  /// The files (`EX`, and audio and video read as files), in the order of
  /// their spans, attachments at `-1` included.
  List<DraftyFile> get files => [
    for (final entity in _linkedEntities) ?entity.asFile,
  ];

  /// The text to show under the attachments: without the images'
  /// placeholders, with line breaks, trimmed.
  String get caption {
    final shown = <String?>[
      for (final rune in text.runes) String.fromCharCode(rune),
    ];
    for (final span in spans) {
      final String? replacement;
      if (span.style == Span.lineBreakStyle) {
        replacement = '\n';
      } else if (_entityOf(span)?.type == Entity.imageType) {
        replacement = null;
      } else {
        continue;
      }
      for (var i = max(span.at, 0); i < span.at + span.length; i++) {
        if (i < shown.length) shown[i] = replacement;
      }
    }
    return shown.nonNulls.join().trim();
  }

  /// The `ref` (and video `preref`) of every image, file, audio and video
  /// entity, as written: what a message tells the server it uses.
  Iterable<String> get fileRefs sync* {
    for (final entity in entities) {
      if (!Entity._fileTypes.contains(entity.type)) continue;
      final data = LooseJson(entity.data);
      if (data.get<String>('ref') case final ref?) yield ref;
      if (data.get<String>('preref') case final ref?) yield ref;
    }
  }

  /// The entities spans point to, each once, in span order.
  Iterable<Entity> get _linkedEntities sync* {
    final seen = <int>{};
    for (final span in spans) {
      if (_entityOf(span) case final entity? when seen.add(span.entityIndex!)) {
        yield entity;
      }
    }
  }

  Entity? _entityOf(Span span) => switch (span.entityIndex) {
    final i? when i >= 0 && i < entities.length => entities[i],
    _ => null,
  };

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

  /// `BR`: a line break over one space.
  static const lineBreakStyle = 'BR';

  /// Where the span starts; `-1` places an entity outside the text, e.g. a
  /// file shown as an attachment.
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

  /// `VC`: a call, see [Drafty.videoCall].
  static const videoCallType = 'VC';

  /// `IM`: an image, see [DraftyImage].
  static const imageType = 'IM';

  /// `EX`: a file, see [DraftyFile].
  static const fileType = 'EX';

  /// `AU`: an audio recording, read as a [DraftyFile].
  static const audioType = 'AU';

  /// `VD`: a video, read as a [DraftyFile].
  static const videoType = 'VD';

  static const Set<String> _fileTypes = {
    imageType,
    fileType,
    audioType,
    videoType,
  };

  final String type;
  final Json data;

  /// The image this entity is, or null for other types.
  DraftyImage? get asImage =>
      type == imageType ? DraftyImage.fromData(data) : null;

  /// The file this entity is (`EX`, `AU` or `VD`), or null for other types.
  DraftyFile? get asFile =>
      type == fileType || type == audioType || type == videoType
      ? DraftyFile.fromData(data)
      : null;

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

/// A file in a Drafty document, sent inline ([inlineData]) or uploaded
/// ([ref]). Read leniently: fields of the wrong type are null.
class DraftyFile with ValueObject {
  const DraftyFile({
    this.mimeType,
    this.name,
    this.size,
    this.ref,
    this.inlineData,
  });

  factory DraftyFile.fromData(Json data) {
    final j = LooseJson(data);
    return DraftyFile(
      mimeType: j.get('mime'),
      name: j.get('name'),
      size: j.get<num>('size')?.toInt(),
      ref: j.get('ref'),
      inlineData: j.get('val'),
    );
  }

  /// `mime`, e.g. `application/pdf`.
  final String? mimeType;
  final String? name;

  /// The size in bytes.
  final int? size;

  /// The URL of the upload, often relative to the server; see
  /// `TinodeConfig.resolveFile`.
  final String? ref;

  /// The file itself as base64 (`val`), for small files sent in the
  /// message.
  final String? inlineData;

  /// [inlineData] decoded; null when absent or not base64.
  Uint8List? get bytes {
    final data = inlineData;
    if (data == null || data.isEmpty) return null;
    try {
      return base64.decode(base64.normalize(data));
    } on FormatException {
      return null;
    }
  }

  /// The entity's `data`.
  Json toData() => {
    'mime': ?mimeType,
    'name': ?name,
    'size': ?size,
    'ref': ?ref,
    'val': ?inlineData,
  };

  @override
  List<Object?> get props => [mimeType, name, size, ref, inlineData];
}

/// An image in a Drafty document: a [DraftyFile] with its size in pixels.
final class DraftyImage extends DraftyFile {
  const DraftyImage({
    super.mimeType,
    super.name,
    super.size,
    super.ref,
    super.inlineData,
    this.width,
    this.height,
  });

  factory DraftyImage.fromData(Json data) {
    final file = DraftyFile.fromData(data);
    final j = LooseJson(data);
    return DraftyImage(
      mimeType: file.mimeType,
      name: file.name,
      size: file.size,
      ref: file.ref,
      inlineData: file.inlineData,
      width: j.get<num>('width')?.toInt(),
      height: j.get<num>('height')?.toInt(),
    );
  }

  final int? width;
  final int? height;

  @override
  Json toData() => {...super.toData(), 'width': ?width, 'height': ?height};

  @override
  List<Object?> get props => [
    mimeType,
    name,
    size,
    ref,
    inlineData,
    width,
    height,
  ];
}
