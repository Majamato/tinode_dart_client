import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/delete_log.dart';
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

/// Reads one part of a topic; `what` names it and the matching key holds
/// its query, e.g. `{"what": "data", "data": {"since": 3}}`.
final class Get extends ClientMessage {
  const Get._(this.topic, this.what, [this.query = const {}]);

  /// [ifModifiedSince] leaves out `public`, `private` and `trusted` when
  /// none of them changed since.
  Get.desc(String topic, {DateTime? ifModifiedSince})
    : this._(topic, 'desc', {'ims': ?ifModifiedSince?.wire});

  /// [ifModifiedSince] returns only the subscriptions changed or removed
  /// since, the unchanged `public` and `private` left out.
  Get.sub(String topic, {DateTime? ifModifiedSince, int? limit})
    : this._(topic, 'sub', {'ims': ?ifModifiedSince?.wire, 'limit': ?limit});

  /// Messages with `since <= seq < before`.
  Get.data(String topic, {int? since, int? before, int? limit})
    : this._(topic, 'data', {
        'since': ?since,
        'before': ?before,
        'limit': ?limit,
      });

  /// Deleted ranges whose delete IDs are `since <= id < before`.
  Get.del(String topic, {int? since, int? before, int? limit})
    : this._(topic, 'del', {
        'since': ?since,
        'before': ?before,
        'limit': ?limit,
      });

  final String topic;
  final String what;
  final Json query;

  /// The lower bound of a `data` or `del` query.
  int? get since => query['since'] as int?;

  /// The upper bound, exclusive, of a `data` or `del` query.
  int? get before => query['before'] as int?;

  @override
  String get type => 'get';

  @override
  Json body() => {
    'topic': topic,
    'what': what,
    if (query.isNotEmpty) what: query,
  };
}

/// Deletes the messages in [ranges]; [hard] deletes them for everyone,
/// otherwise only for this user.
final class Del extends ClientMessage {
  const Del(this.topic, this.ranges, {required this.hard});

  final String topic;
  final List<SeqRange> ranges;
  final bool hard;

  @override
  String get type => 'del';

  @override
  Json body() => {
    'topic': topic,
    'what': 'msg',
    'delseq': [for (final r in ranges) r.toJson()],
    if (hard) 'hard': true,
  };
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
