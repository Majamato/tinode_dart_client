import 'package:async/async.dart';

import 'package:test/test.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import '../support/fake_server.dart';

void main() {
  late FakeServer server;
  late Connection connection;

  setUp(() {
    server = FakeServer();
    connection = Connection(
      server.client,
      timeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() => connection.close());

  test('matches replies to requests by id, in any order', () async {
    final first = connection.request(const Sub('a'));
    final second = connection.request(const Sub('b'));
    final a = await server.next('sub');
    final b = await server.next('sub');
    server
      ..ctrl(b, topic: 'b')
      ..ctrl(a, topic: 'a');
    expect((await first).topic, 'a');
    expect((await second).topic, 'b');
  });

  test('error codes fail the request with ServerException', () async {
    final reply = connection.request(const Sub('usrNOPE'));
    server.ctrl(await server.next('sub'), code: 404);
    await expectLater(
      reply,
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 404)),
    );
  });

  test('a malformed reply fails its request instead of timing out', () async {
    final reply = connection.request(const Sub('a'));
    final sub = await server.next('sub');
    server.send({
      'ctrl': {'id': sub['id'], 'code': 'ok', 'ts': ts},
    });
    await expectLater(reply, throwsA(isA<MalformedPacketException>()));
  });

  test('times out when no reply arrives', () async {
    await expectLater(
      connection.request(const Sub('a')),
      throwsA(isA<RequestTimeoutException>()),
    );
  });

  test('closing the socket fails pending requests', () async {
    final reply = connection.request(const Sub('a'));
    await server.next('sub');
    await server.close();
    await expectLater(reply, throwsA(isA<ConnectionClosedException>()));
  });

  test('unsolicited packets go to events, garbage as errors', () async {
    final events = StreamQueue(connection.events);
    server
      ..send({
        'pres': {'topic': 'me', 'what': 'on'},
      })
      ..sendRaw('not json');
    expect(await events.next, isA<PresMessage>());
    await expectLater(events.next, throwsA(isA<MalformedPacketException>()));
  });

  test('history collects the data packets that precede the ctrl', () async {
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
}
