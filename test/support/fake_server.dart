import 'dart:async';
import 'dart:convert';

import 'package:tinode_dart_client/tinode_dart_client.dart';
import 'package:web_socket/testing.dart';
import 'package:web_socket/web_socket.dart';

const ts = '2026-10-04T11:31:05.654Z';

/// The server end of an in-memory socket pair; [client] is the other end.
final class FakeServer {
  factory FakeServer() {
    final (client, server) = fakes();
    return FakeServer._(client, server);
  }

  FakeServer._(this.client, this._socket) {
    _socket.events.listen((event) {
      if (event case TextDataReceived(:final text)) {
        _received.add(jsonDecode(text) as Json);
      }
    });
  }

  final WebSocket client;
  final WebSocket _socket;
  final _received = StreamController<Json>.broadcast();

  /// Waits for the next client packet of type [name] and returns its body.
  Future<Json> next(String name) async {
    final packet = await _received.stream.firstWhere(
      (p) => p.containsKey(name),
    );
    return packet[name]! as Json;
  }

  void send(Json packet) => _socket.sendText(jsonEncode(packet));

  void sendRaw(String frame) => _socket.sendText(frame);

  void ctrl(Json request, {int code = 200, Json? params, String? topic}) =>
      send({
        'ctrl': {
          'id': request['id'],
          'topic': ?topic,
          'code': code,
          'text': code < 300 ? 'ok' : 'failed',
          'params': ?params,
          'ts': ts,
        },
      });

  /// Answers the next `hi` the way a v0.25 server does.
  Future<void> handshake() async =>
      ctrl(await next('hi'), code: 201, params: {'ver': '0.25'});

  Future<void> close() => _socket.close();
}
