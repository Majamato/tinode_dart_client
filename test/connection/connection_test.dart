import 'dart:typed_data';

import 'package:async/async.dart';

import 'package:test/test.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

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
