import 'dart:convert';

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import '../support/fake_server.dart';

final config = TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'key',
  userAgent: 'test/1.0',
);

void main() {
  late FakeServer server;
  late TinodeClient client;

  setUp(() async {
    server = FakeServer();
    final connecting = TinodeClient.withSocket(server.client, config);
    final hi = await server.next('hi');
    expect(hi, containsPair('ua', 'test/1.0'));
    server.ctrl(hi, code: 201, params: {'ver': '0.25', 'build': 'x'});
    client = await connecting;
  });

  tearDown(() => client.close());

  test('the channels URI carries the API key', () {
    expect(
      config.channelsUri.toString(),
      'ws://localhost:6060/v0/channels?apikey=key',
    );
  });

  test('hi exposes the server info', () {
    expect(client.serverInfo.version, '0.25');
    expect(client.serverInfo.build, 'x');
  });

  test('basic login sends base64 credentials and keeps the user', () async {
    final result = client.loginBasic('alice', 'alice123');
    final login = await server.next('login');
    expect(login['secret'], base64.encode(utf8.encode('alice:alice123')));
    server.ctrl(login, params: {'user': 'usrA', 'token': 'tok', 'expires': ts});
    expect((await result).token, 'tok');
    expect(client.userId, 'usrA');
  });

  test('subscribe returns the name the server assigned', () async {
    final name = client.subscribe('new');
    server.ctrl(await server.next('sub'), topic: 'grpX');
    expect(await name, 'grpX');
  });

  test('getSubscriptions reads meta, or nothing on 204', () async {
    var subs = client.getSubscriptions('me');
    var get = await server.next('get');
    expect(get['what'], 'sub');
    server.send({
      'meta': {
        'id': get['id'],
        'topic': 'me',
        'ts': ts,
        'sub': [
          {'topic': 'usrB', 'seq': 3, 'read': 1},
        ],
      },
    });
    expect((await subs).single.unread, 2);

    subs = client.getSubscriptions('me');
    get = await server.next('get');
    server.ctrl(get, code: 204);
    expect(await subs, isEmpty);
  });

  test('publish marks Drafty content and returns the seq', () async {
    final ack = client.publish(
      'usrB',
      const DraftyContent(Drafty(text: 'hi')),
      noEcho: true,
    );
    final pub = await server.next('pub');
    expect(pub, containsPair('noecho', true));
    expect(pub['head'], {'mime': 'text/x-drafty'});
    expect(pub['content'], {'txt': 'hi'});
    server.ctrl(pub, code: 202, params: {'seq': 9});
    expect((await ack).seq, 9);
  });

  test('getMessages sends only the given bounds', () async {
    final history = client.getMessages('usrB', before: 10, limit: 5);
    final get = await server.next('get');
    expect(get['data'], {'before': 10, 'limit': 5});
    server.ctrl(get, code: 204);
    expect(await history, isEmpty);
  });

  test('notes carry no id', () async {
    client.markRead('usrB', 4);
    expect(await server.next('note'), {
      'topic': 'usrB',
      'what': 'read',
      'seq': 4,
    });
  });

  test('typed streams split unsolicited packets', () async {
    final data = client.messages.first;
    final info = client.info.first;
    server
      ..send({
        'info': {'topic': 'usrB', 'from': 'usrB', 'what': 'kp'},
      })
      ..send({
        'data': {'topic': 'usrB', 'seq': 1, 'ts': ts, 'content': 'yo'},
      });
    expect((await data).content, const PlainText('yo'));
    expect((await info).event, InfoEvent.typing);
  });
}
