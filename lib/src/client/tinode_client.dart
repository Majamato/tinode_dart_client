import 'dart:convert';

import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/client/tinode_config.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/message_content.dart';
import 'package:tinode_dart_client/src/model/subscription.dart';
import 'package:tinode_dart_client/src/model/topic_description.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';
import 'package:web_socket/web_socket.dart';

/// A session with a Tinode server over one WebSocket. There is no logout:
/// [close] it and connect again to switch users.
final class TinodeClient {
  TinodeClient._(this._connection, this.serverInfo);

  static const protocolVersion = '0.25';

  /// Opens the socket and performs the `hi` handshake. An unreachable
  /// server throws `WebSocketException` from `package:web_socket`.
  static Future<TinodeClient> connect(TinodeConfig config) async =>
      withSocket(await WebSocket.connect(config.channelsUri), config);

  /// Like [connect], over an already open [socket].
  static Future<TinodeClient> withSocket(
    WebSocket socket,
    TinodeConfig config,
  ) async {
    final connection = Connection(socket, timeout: config.requestTimeout);
    try {
      final hi = Hi(
        ver: protocolVersion,
        ua: config.userAgent,
        lang: config.language,
      );
      final reply = _ctrl(await connection.request(hi), 'hi');
      return TinodeClient._(connection, ServerInfo.fromParams(reply.params));
    } on Object {
      await connection.close();
      rethrow;
    }
  }

  final Connection _connection;
  final ServerInfo serverInfo;
  String? _userId;

  /// The logged-in user, null before login.
  String? get userId => _userId;

  /// Packets the server sends on its own; replies go to the request methods.
  Stream<ServerMessage> get events => _connection.events;

  Stream<DataMessage> get messages => _only<DataMessage>();

  Stream<PresMessage> get presence => _only<PresMessage>();

  /// Typing, read and received notifications from other users.
  Stream<InfoMessage> get info => _only<InfoMessage>();

  /// Throws [ServerException] on bad credentials, and also on code 300
  /// when the server asks for credential validation.
  Future<LoginResult> loginBasic(String user, String password) =>
      _login('basic', base64.encode(utf8.encode('$user:$password')));

  Future<LoginResult> loginToken(String token) => _login('token', token);

  /// Returns the topic's real name, which differs for `new…` topics.
  Future<String> subscribe(String topic) async {
    final reply = _ctrl(await _connection.request(Sub(topic)), 'sub');
    return reply.topic ?? topic;
  }

  /// Null when the server has nothing to return.
  Future<TopicDescription?> getDescription(String topic) async =>
      switch (await _connection.request(Get(topic, 'desc'))) {
        MetaMessage(:final description) => description,
        _ => null,
      };

  /// On `me` these are the user's chats; elsewhere, the topic's members.
  Future<List<Subscription>> getSubscriptions(String topic) async =>
      switch (await _connection.request(Get(topic, 'sub'))) {
        MetaMessage(:final subscriptions) => subscriptions,
        _ => const [],
      };

  /// Messages with `since <= seq < before`, oldest first. The server
  /// returns the newest [limit] of them (32 by default).
  Future<List<DataMessage>> getMessages(
    String topic, {
    int? since,
    int? before,
    int? limit,
  }) => _connection.history(
    Get(
      topic,
      'data',
      data: {'since': ?since, 'before': ?before, 'limit': ?limit},
    ),
  );

  /// With [noEcho] the sender's own sessions get no `data` copy.
  Future<PublishResult> publish(
    String topic,
    MessageContent content, {
    bool noEcho = false,
  }) async {
    final pub = Pub(topic, content, noEcho: noEcho);
    final reply = _ctrl(await _connection.request(pub), 'pub');
    return PublishResult(
      seq: StrictJson(reply.params).require('seq', 'ctrl.params'),
      time: reply.time,
    );
  }

  /// Tells the topic's other users that this user is typing.
  void sendTyping(String topic) => _connection.notify(Note(topic, 'kp'));

  /// Marks messages up to [seq] as received; the server ignores a [seq]
  /// that does not move the marker forward.
  void markReceived(String topic, int seq) =>
      _connection.notify(Note(topic, 'recv', seq: seq));

  void markRead(String topic, int seq) =>
      _connection.notify(Note(topic, 'read', seq: seq));

  /// With [unsubscribe] the subscription is dropped on every device.
  Future<void> leave(String topic, {bool unsubscribe = false}) async => _ctrl(
    await _connection.request(Leave(topic, unsub: unsubscribe)),
    'leave',
  );

  Future<void> close() => _connection.close();

  Future<LoginResult> _login(String scheme, String secret) async {
    final login = Login(scheme: scheme, secret: secret);
    final params = _ctrl(await _connection.request(login), 'login').params;
    final r = StrictJson(params);
    final result = LoginResult(
      userId: r.require('user', 'ctrl.params'),
      token: r.require('token', 'ctrl.params'),
      expires: r.optionalTime('expires', 'ctrl.params'),
    );
    _userId = result.userId;
    return result;
  }

  Stream<T> _only<T extends ServerMessage>() =>
      events.where((m) => m is T).cast<T>();

  static CtrlMessage _ctrl(ServerMessage reply, String request) =>
      switch (reply) {
        final CtrlMessage ctrl => ctrl,
        _ => throw MalformedPacketException(request, reply),
      };
}
