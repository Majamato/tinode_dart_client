import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
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
        case TextDataReceived(text: '1'):
          probes++;
          _arrived?.complete();
          _arrived = null;
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

  /// Network probes (`1`) the client sent.
  int probes = 0;

  /// Completes with the close code once the client closes the socket.
  Future<int> get closedByClient => _closed.future.timeout(
    const Duration(seconds: 1),
    onTimeout: () => fail('the client did not close the socket'),
  );

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

  /// Waits until the client has sent [count] probes in total.
  Future<void> probed([int count = 1]) async {
    Future<void> wait() async {
      while (probes < count) {
        await (_arrived ??= Completer()).future;
      }
    }

    return wait().timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('$probes of $count probes arrived'),
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

/// Hands out a new [FakeServer] for every connect, as a real server would
/// for every new socket.
final class FakeConnector {
  final _servers = StreamController<FakeServer>();
  late final StreamQueue<FakeServer> _queue = StreamQueue(_servers.stream);

  /// How many connects to refuse before the next one succeeds.
  int refuse = 0;
  int connects = 0;

  Future<WebSocket> call(Uri uri) async {
    connects++;
    if (refuse > 0) {
      refuse--;
      throw WebSocketException('refused');
    }
    final server = FakeServer();
    _servers.add(server);
    return server.client;
  }

  /// The server of the next successful connect.
  Future<FakeServer> next() => _queue.next.timeout(
    const Duration(seconds: 1),
    onTimeout: () => fail('no connect after $connects'),
  );

  /// Fails the test if the client connects again within [wait].
  Future<void> expectNoConnect({
    Duration wait = const Duration(milliseconds: 50),
  }) async {
    final before = connects;
    await Future<void>.delayed(wait);
    expect(connects, before, reason: 'unexpected reconnect');
  }
}
