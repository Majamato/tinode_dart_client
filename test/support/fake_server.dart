import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
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
      switch (event) {
        case TextDataReceived(:final text):
          _inbox.add(jsonDecode(text) as Json);
          _arrived?.complete();
          _arrived = null;
        case CloseReceived(:final code):
          _closed.complete(code);
        case BinaryDataReceived():
      }
    });
  }

  final WebSocket client;
  final WebSocket _socket;

  /// Client packets not yet taken by [next], in arrival order.
  final _inbox = <Json>[];
  Completer<void>? _arrived;
  final _closed = Completer<int>();

  /// Completes with the close code once the client closes the socket.
  Future<int> get closedByClient => _closed.future;

  /// Takes the oldest client packet of type [name] and returns its body,
  /// failing the test if none arrives in time.
  Future<Json> next(String name) async {
    Future<Json> take() async {
      while (true) {
        final i = _inbox.indexWhere((p) => p.containsKey(name));
        if (i != -1) return _inbox.removeAt(i)[name]! as Json;
        await (_arrived ??= Completer()).future;
      }
    }

    return take().timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('no $name packet arrived; inbox: $_inbox'),
    );
  }

  /// Fails the test if the client sent anything [next] did not take.
  Future<void> expectNoMorePackets() async {
    // Fake socket delivery is async; let in-flight packets land first.
    await Future<void>.delayed(Duration.zero);
    expect(_inbox, isEmpty, reason: 'unexpected client packets');
  }

  void send(Json packet) => _socket.sendText(jsonEncode(packet));

  void sendRaw(String frame) => _socket.sendText(frame);

  void sendBinary(Uint8List bytes) => _socket.sendBytes(bytes);

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
