import 'dart:async';
import 'dart:convert';

import 'package:tinode_dart_client/src/connection/pending.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';
import 'package:web_socket/web_socket.dart';

/// Owns the socket: numbers requests, routes replies back to their callers
/// and forwards everything else to [events].
final class Connection {
  Connection(this._socket, {required this.timeout}) {
    _subscription = _socket.events.listen(_onEvent, onDone: _onDone);
  }

  final WebSocket _socket;
  final Duration timeout;
  late final StreamSubscription<WebSocketEvent> _subscription;
  final _events = StreamController<ServerMessage>.broadcast();
  final _pending = <String, PendingRequest>{};
  final _history = <String, HistoryCollector>{};
  var _nextId = 0;
  var _closed = false;

  /// Server packets that are not replies to a request.
  Stream<ServerMessage> get events => _events.stream;

  /// Completes with the `ctrl` or `meta` that answers [message].
  Future<ServerMessage> request(ClientMessage message) {
    final pending = PendingRequest(message.type);
    _send(message, pending);
    return pending.future;
  }

  /// Collects `data` packets for [message], sorted by ascending seq.
  Future<List<DataMessage>> history(Get message) async {
    final topic = message.topic;
    for (var busy = _history[topic]; busy != null; busy = _history[topic]) {
      await busy.done;
    }
    final collector = _history[topic] = HistoryCollector();
    try {
      await request(message);
      return collector.messages..sort((a, b) => a.seq.compareTo(b.seq));
    } finally {
      _history.remove(topic);
      collector.finish();
    }
  }

  /// Sends [message] without waiting for a reply.
  void notify(ClientMessage message) => _send(message, null);

  /// Closes the socket and fails pending requests.
  Future<void> close() async {
    if (_closed) return;
    _onDone(const ConnectionClosedException('closed by client'));
    try {
      await _socket.close(1000);
    } on WebSocketConnectionClosed {
      // The server got there first.
    }
  }

  /// Numbers [message] and sends it over the socket.
  void _send(ClientMessage message, PendingRequest? pending) {
    if (_closed) {
      pending?.fail(const ConnectionClosedException('closed'));
      return;
    }
    String? id;
    if (pending != null) {
      id = '${++_nextId}';
      _pending[id] = pending;
      pending.startTimer(timeout, () => _pending.remove(id));
    }
    try {
      _socket.sendText(jsonEncode(message.toJson(id)));
    } on WebSocketConnectionClosed {
      _onDone(const ConnectionClosedException('socket closed'));
    }
  }

  /// Handles an incoming socket event.
  void _onEvent(WebSocketEvent event) {
    switch (event) {
      case TextDataReceived(:final text):
        _onFrame(text);
      case CloseReceived(:final code, :final reason):
        _onDone(ConnectionClosedException('$code $reason'.trim()));
      case BinaryDataReceived():
        _events.addError(const MalformedPacketException(r'$', 'binary frame'));
    }
  }

  /// Decodes a text frame into a single-key packet.
  void _onFrame(String frame) {
    final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      _events.addError(MalformedPacketException(r'$', frame));
      return;
    }
    if (decoded case final Json packet when packet.length == 1) {
      final MapEntry(:key, :value) = packet.entries.first;
      if (value case final Json body) return _dispatch(key, body);
    }
    _events.addError(MalformedPacketException(r'$', decoded));
  }

  /// Parses a packet and routes it or fails its waiter.
  void _dispatch(String key, Json body) {
    final ServerMessage? message;
    try {
      message = ServerMessage.fromPacket(key, body);
    } on MalformedPacketException catch (e) {
      // Fail the waiting request rather than letting it time out.
      final pending = _pending.remove(body['id']);
      pending == null ? _events.addError(e) : pending.fail(e);
      return;
    }
    if (message != null) _route(message);
  }

  /// Delivers a message to its waiter, history, or events.
  void _route(ServerMessage message) {
    final id = switch (message) {
      CtrlMessage(:final id) || MetaMessage(:final id) => id,
      _ => null,
    };
    if (id != null) {
      // A reply whose request timed out has no waiter left; drop it.
      _pending.remove(id)?.complete(message);
    } else if (message is DataMessage && _history[message.topic] != null) {
      _history[message.topic]!.messages.add(message);
    } else {
      _events.add(message);
    }
  }

  /// Tears down the connection and fails pending requests.
  void _onDone([TinodeException? error]) {
    if (_closed) return;
    _closed = true;
    final reason = error ?? const ConnectionClosedException('socket closed');
    for (final pending in _pending.values) {
      pending.fail(reason);
    }
    _pending.clear();
    unawaited(_subscription.cancel());
    unawaited(_events.close());
  }
}
