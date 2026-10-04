import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/drafty.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// The body of a message: a plain string, a [Drafty] document, or
/// something this client does not understand (kept as-is).
sealed class MessageContent with ValueObject {
  const MessageContent();

  factory MessageContent.fromJson(Object? content) => switch (content) {
    final String text => PlainText(text),
    final Json json => DraftyContent(Drafty.fromJson(json)),
    _ => UnknownContent(content),
  };

  /// The plain text without formatting, empty when unknown.
  String get text;

  Object? toJson();
}

final class PlainText extends MessageContent {
  const PlainText(this.text);

  @override
  final String text;

  @override
  Object? toJson() => text;

  @override
  List<Object?> get props => [text];
}

final class DraftyContent extends MessageContent {
  const DraftyContent(this.drafty);

  final Drafty drafty;

  @override
  String get text => drafty.text;

  @override
  Object? toJson() => drafty.toJson();

  @override
  List<Object?> get props => [drafty];
}

final class UnknownContent extends MessageContent {
  const UnknownContent(this.raw);

  final Object? raw;

  @override
  String get text => '';

  @override
  Object? toJson() => raw;

  @override
  List<Object?> get props => [raw];
}
