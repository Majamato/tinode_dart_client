import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/message_content.dart';
import 'package:tinode_dart_client/src/model/message_head.dart';

/// A packet sent to the server. The `id` passed to [toJson] is null only
/// for packets that get no reply (`note`).
sealed class ClientMessage {
  const ClientMessage();

  /// The packet type, e.g. `sub`.
  String get type;

  Json body();

  Json toJson(String? id) => {
    type: {'id': ?id, ...body()},
  };
}

final class Hi extends ClientMessage {
  const Hi({required this.ver, required this.ua, this.lang});

  final String ver;
  final String ua;
  final String? lang;

  @override
  String get type => 'hi';

  @override
  Json body() => {'ver': ver, 'ua': ua, 'lang': ?lang};
}

final class Login extends ClientMessage {
  const Login({required this.scheme, required this.secret});

  final String scheme;
  final String secret;

  @override
  String get type => 'login';

  @override
  Json body() => {'scheme': scheme, 'secret': secret};
}

final class Sub extends ClientMessage {
  const Sub(this.topic);

  final String topic;

  @override
  String get type => 'sub';

  @override
  Json body() => {'topic': topic};
}

final class Leave extends ClientMessage {
  const Leave(this.topic, {required this.unsub});

  final String topic;
  final bool unsub;

  @override
  String get type => 'leave';

  @override
  Json body() => {'topic': topic, if (unsub) 'unsub': true};
}

/// `what` is one of `desc`, `sub`, `data`; [data] holds `since`/`before`/`limit`.
final class Get extends ClientMessage {
  const Get(this.topic, this.what, {this.data});

  final String topic;
  final String what;
  final Json? data;

  @override
  String get type => 'get';

  @override
  Json body() => {'topic': topic, 'what': what, 'data': ?data};
}

/// [head] adds to the `mime` that Drafty content gets.
final class Pub extends ClientMessage {
  const Pub(this.topic, this.content, {required this.noEcho, this.head});

  final String topic;
  final MessageContent content;
  final bool noEcho;
  final Json? head;

  @override
  String get type => 'pub';

  @override
  Json body() {
    final head = {
      if (content is DraftyContent) 'mime': MessageHead.draftyMime,
      ...?this.head,
    };
    return {
      'topic': topic,
      if (noEcho) 'noecho': true,
      if (head.isNotEmpty) 'head': head,
      'content': content.toJson(),
    };
  }
}

/// [event] and [payload] are for `call` notes only.
final class Note extends ClientMessage {
  const Note(this.topic, this.what, {this.seq, this.event, this.payload});

  final String topic;
  final String what;
  final int? seq;
  final String? event;
  final Json? payload;

  @override
  String get type => 'note';

  @override
  Json body() => {
    'topic': topic,
    'what': what,
    'seq': ?seq,
    'event': ?event,
    'payload': ?payload,
  };
}
