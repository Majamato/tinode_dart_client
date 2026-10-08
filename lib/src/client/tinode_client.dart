import 'dart:convert';

import 'package:tinode_dart_client/src/client/connection_status.dart';
import 'package:tinode_dart_client/src/client/connection_supervisor.dart';
import 'package:tinode_dart_client/src/client/requests.dart';
import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/client/tinode_config.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/call.dart';
import 'package:tinode_dart_client/src/model/delete_log.dart';
import 'package:tinode_dart_client/src/model/drafty.dart';
import 'package:tinode_dart_client/src/model/message_content.dart';
import 'package:tinode_dart_client/src/model/subscription.dart';
import 'package:tinode_dart_client/src/model/topic_description.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';
import 'package:web_socket/web_socket.dart';

/// The code of a `get` whose `ims` found nothing changed.
const _notModified = 304;

/// A connection to a Tinode server that outlives dropped sockets: see
/// [status]. There is no logout: [close] it and connect again to switch
/// users.
final class TinodeClient {
  TinodeClient._(this._supervisor) {
    // A login the client makes on its own, after a reconnect or restore.
    _supervisor.statusChanges.listen((status) {
      if (status case Connected(:final login?)) _userId = login.userId;
    });
  }

  /// Starts a client for a user who logged in before, without waiting
  /// for the server, so an app can open offline. It returns at once in
  /// [Reconnecting] and connects in the background as after a drop: with
  /// backoff, logging in with [token]. [Connected.login] then carries the
  /// renewed token; a refused token ends in [Disconnected].
  ///
  /// Until the first `hi` is answered, [serverInfo] is
  /// [ServerInfo.unknown] and [userId] is null.
  factory TinodeClient.restore(
    TinodeConfig config, {
    required String token,
    SocketConnector connector = WebSocket.connect,
  }) => TinodeClient._(
    ConnectionSupervisor.restore(config, connector, token: token),
  );

  static const String protocolVersion = wireVersion;

  /// Opens the socket and performs the `hi` handshake; an unreachable
  /// server throws [ServerUnreachableException]. Pass [connector] to tune
  /// the socket, e.g. `dart:io` ping frames.
  static Future<TinodeClient> connect(
    TinodeConfig config, {
    SocketConnector connector = WebSocket.connect,
  }) async =>
      TinodeClient._(await ConnectionSupervisor.open(config, connector));

  final ConnectionSupervisor _supervisor;
  String? _userId;

  /// The server's reply to the latest `hi`.
  ServerInfo get serverInfo => _supervisor.serverInfo;

  /// The logged-in user, null before login.
  String? get userId => _userId;

  /// While not [Connected], requests fail with
  /// [ConnectionClosedException] and notes are dropped.
  ConnectionStatus get status => _supervisor.status;

  /// Changes of [status]; ends after [Disconnected].
  Stream<ConnectionStatus> get statusChanges => _supervisor.statusChanges;

  /// Packets the server sends on its own; replies go to the request
  /// methods. It spans reconnects and ends after [Disconnected].
  Stream<ServerMessage> get events => _supervisor.events;

  Stream<DataMessage> get messages => _only<DataMessage>();

  Stream<PresMessage> get presence => _only<PresMessage>();

  /// Typing, read and received notifications from other users, and the
  /// steps of calls.
  Stream<InfoMessage> get info => _only<InfoMessage>();

  /// Throws [ServerException] on bad credentials, and also on code 300
  /// when the server asks for credential validation.
  Future<LoginResult> loginBasic(String user, String password) =>
      _login('basic', base64.encode(utf8.encode('$user:$password')));

  Future<LoginResult> loginToken(String token) => _login('token', token);

  /// Returns the topic's real name, which differs for `new…` topics.
  /// The topic is attached again after a reconnect.
  Future<String> subscribe(String topic) async {
    final name = await _supervisor.connection.attach(topic);
    _supervisor.attached.add(name);
    return name;
  }

  /// Null when the server has nothing to return. With [ifModifiedSince],
  /// `public`, `private` and `trusted` are left out unless one of them
  /// changed since; the counters always come.
  Future<TopicDescription?> getDescription(
    String topic, {
    DateTime? ifModifiedSince,
  }) async => switch (await _supervisor.connection.request(
    Get.desc(topic, ifModifiedSince: ifModifiedSince),
  )) {
    MetaMessage(:final description) => description,
    _ => null,
  };

  /// On `me` these are the user's chats; elsewhere, the topic's members.
  ///
  /// With [ifModifiedSince] only the subscriptions changed since come back,
  /// and those removed since carry `deleted`. A `public` or `private` left
  /// out of them is unchanged, not cleared. Nothing changed gives `[]`.
  Future<List<Subscription>> getSubscriptions(
    String topic, {
    DateTime? ifModifiedSince,
    int? limit,
  }) async {
    final get = Get.sub(topic, ifModifiedSince: ifModifiedSince, limit: limit);
    try {
      return switch (await _supervisor.connection.request(get)) {
        MetaMessage(:final subscriptions) => subscriptions,
        _ => const [],
      };
    } on ServerException catch (e) {
      if (e.code == _notModified) return const [];
      rethrow;
    }
  }

  /// Messages with `since <= seq < before`, oldest first. The server
  /// returns the newest [limit] of them (32 by default).
  Future<List<DataMessage>> getMessages(
    String topic, {
    int? since,
    int? before,
    int? limit,
  }) async => _supervisor.connection.history(
    Get.data(topic, since: since, before: before, limit: limit),
  );

  /// The messages deleted by delete IDs `since <= id < before`, for
  /// catching up on deletions missed while away; see
  /// [Subscription.lastDeleteId]. The server returns the oldest [limit] of
  /// them (32 by default).
  Future<DeleteLog> getDeleteLog(
    String topic, {
    int? since,
    int? before,
    int? limit,
  }) async => switch (await _supervisor.connection.request(
    Get.del(topic, since: since, before: before, limit: limit),
  )) {
    MetaMessage(:final deleteLog?) => deleteLog,
    _ => DeleteLog.empty,
  };

  /// With [noEcho] the sender's own sessions get no `data` copy. [head]
  /// adds headers; keys of your own start with `x-<app>-`.
  Future<PublishResult> publish(
    String topic,
    MessageContent content, {
    bool noEcho = false,
    Json? head,
  }) => _publish(Pub(topic, content, noEcho: noEcho, head: head));

  /// Deletes the messages in [ranges] and returns the deletion's delete
  /// ID. By default only for this user; [hard] deletes them for everyone,
  /// which needs the `D` permission. Without it the server deletes them
  /// for this user only, without an error.
  Future<int> deleteMessages(
    String topic,
    List<SeqRange> ranges, {
    bool hard = false,
  }) async {
    if (ranges.isEmpty) {
      throw ArgumentError.value(ranges, 'ranges', 'must not be empty');
    }
    final reply = await _supervisor.connection.ctrl(
      Del(topic, ranges, hard: hard),
    );
    return StrictJson(reply.params).require('del', 'ctrl.params');
  }

  /// Calls the peer of the 1:1 [topic] by publishing a call message. Its
  /// seq names the call in [sendCallEvent], and the server updates the
  /// message as the call goes on. Throws [ServerException] 486 while the
  /// chat already has a call, 403 outside 1:1 chats and 501 when the
  /// server has no ICE servers.
  Future<PublishResult> startCall(String topic, {bool audioOnly = false}) =>
      _publish(
        Pub(
          topic,
          DraftyContent(Drafty.videoCall(audioOnly: audioOnly)),
          noEcho: false,
          head: {
            'webrtc': CallState.started.wire,
            if (audioOnly) 'aonly': true,
          },
        ),
      );

  /// Sends one step of call [seq] to the peer in [topic]; an `offer`,
  /// `answer` or `iceCandidate` carries its [payload].
  ///
  /// Unlike the other notes, it throws [ConnectionClosedException] while
  /// not [Connected] instead of dropping the note: a lost step leaves the
  /// peer waiting. The server ends calls whose session dropped anyway.
  void sendCallEvent(String topic, int seq, CallEvent event, {Json? payload}) {
    if (event == CallEvent.unknown) {
      throw ArgumentError.value(event, 'event', 'cannot be sent');
    }
    if (seq <= 0) throw ArgumentError.value(seq, 'seq', 'must be positive');
    _supervisor.connection.notify(
      Note(topic, 'call', seq: seq, event: event.wire, payload: payload),
    );
  }

  /// Tells the topic's other users that this user is typing.
  void sendTyping(String topic) => _supervisor.ready?.notify(Note(topic, 'kp'));

  /// Marks messages up to [seq] as received; the server ignores a [seq]
  /// that does not move the marker forward.
  void markReceived(String topic, int seq) =>
      _supervisor.ready?.notify(Note(topic, 'recv', seq: seq));

  void markRead(String topic, int seq) =>
      _supervisor.ready?.notify(Note(topic, 'read', seq: seq));

  /// With [unsubscribe] the subscription is dropped on every device.
  /// Without it, leaving while disconnected succeeds: there is nothing
  /// attached on the server to leave.
  Future<void> leave(String topic, {bool unsubscribe = false}) async {
    _supervisor.attached.remove(topic);
    if (_supervisor.ready case final connection?) {
      await connection.ctrl(Leave(topic, unsub: unsubscribe));
    } else if (unsubscribe) {
      throw const ConnectionClosedException('not connected');
    }
  }

  /// Closes the socket on purpose, e.g. while the app is in the background.
  /// Requests fail until [resume].
  void suspend() => _supervisor.suspend();

  /// Reconnects at once, skipping the backoff wait; while [Connected], it
  /// probes the socket instead. Call it when the app returns to the
  /// foreground or the network changes. After a network change a dead
  /// socket is likely, so a short [probeTimeout] finds it sooner.
  void resume({Duration? probeTimeout}) =>
      _supervisor.resume(probeTimeout: probeTimeout);

  Future<void> close() => _supervisor.close();

  Future<LoginResult> _login(String scheme, String secret) async {
    final result = await _supervisor.connection.login(scheme, secret);
    _supervisor.token = result.token;
    _userId = result.userId;
    return result;
  }

  Future<PublishResult> _publish(Pub pub) async {
    final reply = await _supervisor.connection.ctrl(pub);
    return PublishResult(
      seq: StrictJson(reply.params).require('seq', 'ctrl.params'),
      time: reply.time,
    );
  }

  Stream<T> _only<T extends ServerMessage>() =>
      events.where((m) => m is T).cast<T>();
}
