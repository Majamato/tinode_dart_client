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

  /// The top-level `extra` beside the packet, e.g. the files it uses.
  Json? extra() => null;

  Json toJson(String? id) => {
    type: {'id': ?id, ...body()},
    'extra': ?extra(),
  };
}

/// `extra` naming the uploaded files a packet refers to, so the server
/// keeps them; null when there are none.
Json? _attachments(List<String> paths) =>
    paths.isEmpty ? null : {'attachments': paths};

/// [dev] is the device token for push notifications and [platf] its OS.
final class Hi extends ClientMessage {
  const Hi({
    required this.ver,
    required this.ua,
    this.lang,
    this.dev,
    this.platf,
  });

  final String ver;
  final String ua;
  final String? lang;
  final String? dev;
  final String? platf;

  @override
  String get type => 'hi';

  @override
  Json body() => {
    'ver': ver,
    'ua': ua,
    'lang': ?lang,
    'dev': ?dev,
    'platf': ?platf,
  };
}

/// [codes] confirm credentials, by method, e.g. `{'email': '123456'}`.
final class Login extends ClientMessage {
  const Login({
    required this.scheme,
    required this.secret,
    this.codes = const {},
  });

  final String scheme;
  final String secret;
  final Map<String, String> codes;

  @override
  String get type => 'login';

  @override
  Json body() => {
    'scheme': scheme,
    'secret': secret,
    if (codes.isNotEmpty)
      'cred': [
        for (final MapEntry(:key, :value) in codes.entries)
          {'meth': key, 'resp': value},
      ],
  };
}

/// [init] sets up a topic that the `sub` creates (`new…`, `nch…`);
/// [attachments] are the uploads its profile uses.
final class Sub extends ClientMessage {
  const Sub(this.topic, {this.init, this.attachments = const []});

  final String topic;
  final TopicChanges? init;
  final List<String> attachments;

  @override
  String get type => 'sub';

  @override
  Json body() => {'topic': topic, 'set': ?init?.toJson()};

  @override
  Json? extra() => _attachments(attachments);
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
  /// since, the unchanged `public` and `private` left out. [userId] asks
  /// for that one member only.
  Get.sub(String topic, {DateTime? ifModifiedSince, int? limit, String? userId})
    : this._(topic, 'sub', {
        'ims': ?ifModifiedSince?.wire,
        'limit': ?limit,
        'user': ?userId,
      });

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

/// What a `set` changes: the topic's description, a subscription, the
/// tags. A `sub` that creates a topic carries the same object.
final class TopicChanges {
  const TopicChanges({this.desc, this.sub, this.tags});

  /// `public`, `private`, `defacs`.
  final Json? desc;

  /// `user` (another user's subscription; the own one without it) and
  /// `mode`.
  final Json? sub;
  final List<String>? tags;

  Json toJson() => {'desc': ?desc, 'sub': ?sub, 'tags': ?tags};
}

/// The `set` packet, named apart from `dart:core`'s `Set`. [attachments]
/// are the uploads the new profile uses.
final class SetMeta extends ClientMessage {
  const SetMeta(this.topic, this.changes, {this.attachments = const []});

  final String topic;
  final TopicChanges changes;
  final List<String> attachments;

  @override
  String get type => 'set';

  @override
  Json body() => {'topic': topic, ...changes.toJson()};

  @override
  Json? extra() => _attachments(attachments);
}

/// Deletes one kind of thing; `what` names it.
final class Del extends ClientMessage {
  const Del._(
    this.topic,
    this.what, {
    this.hard = false,
    this.fields = const {},
  });

  /// The messages in [ranges]; [hard] deletes them for everyone, otherwise
  /// only for this user.
  Del.messages(String topic, List<SeqRange> ranges, {required bool hard})
    : this._(
        topic,
        'msg',
        hard: hard,
        fields: {
          'delseq': [for (final r in ranges) r.toJson()],
        },
      );

  /// The whole topic, with its messages and subscriptions.
  const Del.topic(String topic) : this._(topic, 'topic', hard: true);

  /// Another member's subscription to [topic].
  Del.subscription(String topic, String userId)
    : this._(topic, 'sub', fields: {'user': userId});

  /// The logged-in user's account.
  const Del.user() : this._('me', 'user', hard: true);

  final String topic;
  final String what;
  final bool hard;
  final Json fields;

  @override
  String get type => 'del';

  @override
  Json body() => {
    'topic': topic,
    'what': what,
    ...fields,
    if (hard) 'hard': true,
  };
}

/// Creates an account or changes the logged-in user's login and password.
/// [user] is `new` to create one, null for the logged-in user. A
/// [tmpScheme] and [tmpSecret] authorise one request on a session that
/// isn't logged in, e.g. with a password reset code. [credentials] are
/// the new account's to confirm, by method, e.g. `{'email': 'a@b.c'}`.
final class Acc extends ClientMessage {
  const Acc({
    required this.scheme,
    required this.secret,
    this.user,
    this.login = false,
    this.tags,
    this.desc,
    this.tmpScheme,
    this.tmpSecret,
    this.credentials = const {},
  });

  final String scheme;
  final String secret;
  final String? user;
  final bool login;
  final List<String>? tags;
  final Json? desc;
  final String? tmpScheme;
  final String? tmpSecret;
  final Map<String, String> credentials;

  @override
  String get type => 'acc';

  @override
  Json body() => {
    'user': ?user,
    'scheme': scheme,
    'secret': secret,
    if (login) 'login': true,
    'tags': ?tags,
    'desc': ?desc,
    'tmpscheme': ?tmpScheme,
    'tmpsecret': ?tmpSecret,
    if (credentials.isNotEmpty)
      'cred': [
        for (final MapEntry(:key, :value) in credentials.entries)
          {'meth': key, 'val': value},
      ],
  };
}

/// [head] adds to the `mime` that Drafty content gets; [attachments] are
/// the uploads the content refers to.
final class Pub extends ClientMessage {
  const Pub(
    this.topic,
    this.content, {
    required this.noEcho,
    this.head,
    this.attachments = const [],
  });

  final String topic;
  final MessageContent content;
  final bool noEcho;
  final Json? head;
  final List<String> attachments;

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

  @override
  Json? extra() => _attachments(attachments);
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
