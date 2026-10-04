import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// Message headers (`head`). Common keys are typed; [raw] keeps the rest.
final class MessageHead with ValueObject {
  const MessageHead({
    this.mime,
    this.replaces,
    this.replyTo,
    this.raw = const {},
  });

  factory MessageHead.fromJson(Json json) {
    final j = LooseJson(json);
    return MessageHead(
      mime: j.get('mime'),
      replaces: j.get('replace'),
      replyTo: j.get('reply'),
      raw: json,
    );
  }

  static const draftyMime = 'text/x-drafty';

  final String? mime;

  /// `:<seq>` of the message this one edits.
  final String? replaces;

  /// `<topic>:<seq>` of the message this one replies to.
  final String? replyTo;
  final Json raw;

  @override
  List<Object?> get props => [mime, replaces, replyTo, raw];
}
