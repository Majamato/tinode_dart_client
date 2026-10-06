import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';

import 'package:test/test.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';
import 'package:web_socket/web_socket.dart';

import '../support/fake_server.dart';

const timeout = Duration(milliseconds: 200);

void main() {
  late FakeServer server;
  late Connection connection;

  setUp(() {
    server = FakeServer();
    connection = Connection(server.client, timeout: timeout);
  });

  tearDown(() => connection.close());

  test('matches replies to requests by id, in any order', () async {
    final first = connection.request(const Sub('a'));
    final second = connection.request(const Sub('b'));
    final a = await server.next('sub');
    final b = await server.next('sub');
    expect(a['id'], isNot(b['id']));
    server
      ..ctrl(b, topic: 'b')
      ..ctrl(a, topic: 'a');
    expect((await first).topic, 'a');
    expect((await second).topic, 'b');
  });

  test('a meta reply completes its request too', () async {
    final reply = connection.request(const Get('me', 'desc'));
    final get = await server.next('get');
    server.send({
      'meta': {
        'id': get['id'],
        'topic': 'me',
        'ts': ts,
        'desc': <String, Object?>{},
      },
    });
    expect(await reply, isA<MetaMessage>());
  });

  test('error codes fail the request with ServerException', () async {
    final reply = connection.request(const Sub('usrNOPE'));
    server.ctrl(await server.next('sub'), code: 404, params: {'what': 'topic'});
    await expectLater(
      reply,
      throwsA(
        isA<ServerException>()
            .having((e) => e.code, 'code', 404)
            .having((e) => e.text, 'text', 'failed')
            .having((e) => e.params, 'params', {'what': 'topic'}),
      ),
    );
  });

  test('a malformed reply fails its request instead of timing out', () async {
    final reply = connection.request(const Sub('a'));
    final sub = await server.next('sub');
    server.send({
      'ctrl': {'id': sub['id'], 'code': 'ok', 'ts': ts},
    });
    await expectLater(
      reply,
      throwsA(
        isA<MalformedPacketException>().having(
          (e) => e.path,
          'path',
          'ctrl.code',
        ),
      ),
    );
  });

  group('timeout', () {
    test('fails the request, naming it and the limit', () async {
      await expectLater(
        connection.request(const Sub('a')),
        throwsA(
          isA<RequestTimeoutException>()
              .having((e) => e.request, 'request', 'sub')
              .having((e) => e.timeout, 'timeout', timeout),
        ),
      );
    });

    test('a late reply is dropped, not sent to events', () async {
      final events = <ServerMessage>[];
      connection.events.listen(events.add);
      final late = connection.request(const Sub('a'));
      final sub = await server.next('sub');
      await expectLater(late, throwsA(isA<RequestTimeoutException>()));

      server.ctrl(sub, topic: 'a');
      final next = connection.request(const Sub('b'));
      server.ctrl(await server.next('sub'), topic: 'b');
      expect((await next).topic, 'b');
      expect(events, isEmpty);
    });
  });

  group('closing', () {
    test('by the server fails pending requests', () async {
      final reply = connection.request(const Sub('a'));
      await server.next('sub');
      await server.close();
      await expectLater(reply, throwsA(isA<ConnectionClosedException>()));
    });

    test(
      'by the client fails pending requests and closes the socket',
      () async {
        final reply = connection.request(const Sub('a'));
        await server.next('sub');
        final failed = expectLater(
          reply,
          throwsA(isA<ConnectionClosedException>()),
        );
        await connection.close();
        await failed;
        expect(await server.closedByClient, 1000);
      },
    );

    test('twice is harmless', () async {
      await connection.close();
      await connection.close();
      expect(await server.closedByClient, 1000);
    });

    test('a socket error ends the connection like a close', () async {
      final socket = ErrorSocket();
      final failing = Connection(socket, timeout: timeout);
      final reply = failing.request(const Sub('a'));
      socket.controller.addError(WebSocketException('reset by peer'));
      await expectLater(reply, throwsA(isA<ConnectionClosedException>()));
      expect(
        await failing.done,
        isA<ConnectionClosedException>().having(
          (e) => e.reason,
          'reason',
          contains('reset by peer'),
        ),
      );
    });

    test('done carries the reason', () async {
      await connection.close();
      expect(
        await connection.done,
        isA<ConnectionClosedException>().having(
          (e) => e.reason,
          'reason',
          'closed by client',
        ),
      );
    });

    test('ends the events stream', () async {
      final done = connection.events.toList();
      await server.close();
      expect(await done, isEmpty);
    });

    test('later requests fail at once and send nothing', () async {
      await connection.close();
      await expectLater(
        connection.request(const Sub('a')),
        throwsA(isA<ConnectionClosedException>()),
      );
      connection.notify(const Note('a', 'kp'));
      await server.expectNoMorePackets();
    });
  });

  group('unsolicited packets', () {
    test('go to events, garbage as errors', () async {
      final events = StreamQueue(connection.events);
      server
        ..send({
          'pres': {'topic': 'me', 'what': 'on'},
        })
        ..sendRaw('not json');
      expect(await events.next, isA<PresMessage>());
      await expectLater(events.next, throwsA(isA<MalformedPacketException>()));
    });

    test('of an unknown type are dropped silently', () async {
      final events = StreamQueue(connection.events);
      server
        ..send({
          'future': {'topic': 'me'},
        })
        ..send({
          'pres': {'topic': 'me', 'what': 'on'},
        });
      expect(await events.next, isA<PresMessage>());
    });

    test('that are not one-key JSON objects are errors', () async {
      final events = StreamQueue(connection.events);
      server
        ..sendRaw('[1]')
        ..send({
          'pres': {'topic': 'me', 'what': 'on'},
          'info': {'topic': 'me', 'from': 'usrA', 'what': 'kp'},
        })
        ..sendRaw('{"pres":"on"}')
        ..sendBinary(Uint8List(1))
        ..send({
          'pres': {'topic': 'me', 'what': 'off'},
        });
      for (var i = 0; i < 4; i++) {
        await expectLater(
          events.next,
          throwsA(isA<MalformedPacketException>()),
        );
      }
      // Errors do not end the stream.
      expect(await events.next, isA<PresMessage>());
    });
  });

  group('probing', () {
    test('a probe can set its own deadline, once', () async {
      final peer = FakeServer();
      final probed = Connection(
        peer.client,
        timeout: timeout,
        probeAfter: const Duration(milliseconds: 30),
        probeTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(probed.close);

      probed.probe(timeout: const Duration(milliseconds: 100));
      await peer.probed();
      peer.sendRaw('0');

      // The next probe comes from idleness and gets the default deadline.
      await peer.probed(2);
      final clock = Stopwatch()..start();
      await probed.done;
      expect(clock.elapsed, greaterThan(const Duration(milliseconds: 200)));
    });

    test('a probe answer is neither an event nor an error', () async {
      final events = StreamQueue(connection.events);
      server
        ..sendRaw('0')
        ..send({
          'pres': {'topic': 'me', 'what': 'on'},
        });
      expect(await events.next, isA<PresMessage>());
    });

    test('an unanswered probe ends the connection', () async {
      final probed = Connection(
        FakeServer().client,
        timeout: timeout,
        probeTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(probed.close);
      final reply = probed.request(const Sub('a'));
      probed.probe();
      await expectLater(reply, throwsA(isA<ConnectionClosedException>()));
      expect(
        await probed.done,
        isA<ConnectionClosedException>().having(
          (e) => e.reason,
          'reason',
          'probe unanswered',
        ),
      );
    });

    test('any frame counts as the answer', () async {
      final peer = FakeServer();
      final probed = Connection(
        peer.client,
        timeout: timeout,
        probeTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(probed.close);
      probed.probe();
      await peer.probed();
      peer.send({
        'pres': {'topic': 'me', 'what': 'on'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(probed.isClosed, isFalse);
    });
  });

  group('history', () {
    test('collects the data packets that precede the ctrl', () async {
      final events = <ServerMessage>[];
      connection.events.listen(events.add);
      final history = connection.history(const Get('usrB', 'data'));
      final get = await server.next('get');
      for (final seq in [8, 7]) {
        server.send({
          'data': {'topic': 'usrB', 'seq': seq, 'ts': ts, 'content': '$seq'},
        });
      }
      server
        ..send({
          'data': {'topic': 'usrC', 'seq': 1, 'ts': ts, 'content': 'live'},
        })
        ..ctrl(get, code: 208, params: {'count': 2});
      final messages = await history;
      expect(messages.map((m) => m.seq), [7, 8]);
      expect(events.single, isA<DataMessage>());
    });

    test('requests for one topic run one at a time', () async {
      final first = connection.history(const Get('usrB', 'data'));
      final second = connection.history(const Get('usrB', 'data'));
      final get = await server.next('get');
      await server.expectNoMorePackets();

      server
        ..send({
          'data': {'topic': 'usrB', 'seq': 1, 'ts': ts, 'content': 'one'},
        })
        ..ctrl(get, code: 208);
      expect((await first).map((m) => m.seq), [1]);

      final get2 = await server.next('get');
      server
        ..send({
          'data': {'topic': 'usrB', 'seq': 2, 'ts': ts, 'content': 'two'},
        })
        ..ctrl(get2, code: 208);
      expect((await second).map((m) => m.seq), [2]);
    });

    test('a failed request frees the topic for the next one', () async {
      final failed = connection.history(const Get('usrB', 'data'));
      server.ctrl(await server.next('get'), code: 403);
      await expectLater(failed, throwsA(isA<ServerException>()));

      final retry = connection.history(const Get('usrB', 'data'));
      server.ctrl(await server.next('get'), code: 204);
      expect(await retry, isEmpty);
    });

    test('a timed out request frees the topic for the next one', () async {
      final failed = connection.history(const Get('usrB', 'data'));
      await server.next('get');
      await expectLater(failed, throwsA(isA<RequestTimeoutException>()));

      final retry = connection.history(const Get('usrB', 'data'));
      server.ctrl(await server.next('get'), code: 204);
      expect(await retry, isEmpty);
    });
  });
}

/// A socket whose event stream the test drives directly.
final class ErrorSocket implements WebSocket {
  final controller = StreamController<WebSocketEvent>();

  @override
  Stream<WebSocketEvent> get events => controller.stream;

  @override
  String get protocol => '';

  @override
  void sendText(String s) {}

  @override
  void sendBytes(Uint8List b) {}

  @override
  Future<void> close([int? code, String? reason]) => controller.close();
}
