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
  group('channelsUri', () {
    Uri channels(String server) => TinodeConfig(
      server: Uri.parse(server),
      apiKey: 'key',
      userAgent: 'test/1.0',
    ).channelsUri;

    test('carries the API key', () {
      expect(
        config.channelsUri.toString(),
        'ws://localhost:6060/v0/channels?apikey=key',
      );
    });

    test('keeps a base path, with or without a trailing slash', () {
      for (final server in ['wss://host/chat', 'wss://host/chat/']) {
        expect(
          channels(server).toString(),
          'wss://host/chat/v0/channels?apikey=key',
        );
      }
      expect(
        channels('wss://host/').toString(),
        'wss://host/v0/channels?apikey=key',
      );
    });

    test('keeps existing query parameters', () {
      expect(channels('wss://host?region=eu').queryParameters, {
        'region': 'eu',
        'apikey': 'key',
      });
    });
  });

  group('connecting', () {
    test('hi carries version, user agent and language', () async {
      final server = FakeServer();
      final connecting = TinodeClient.withSocket(
        server.client,
        TinodeConfig(
          server: config.server,
          apiKey: 'key',
          userAgent: 'test/1.0',
          language: 'en-US',
        ),
      );
      final hi = await server.next('hi');
      expect(hi, {
        'id': isA<String>(),
        'ver': TinodeClient.protocolVersion,
        'ua': 'test/1.0',
        'lang': 'en-US',
      });
      server.ctrl(hi, code: 201, params: {'ver': '0.25', 'build': 'x'});
      final client = await connecting;
      addTearDown(client.close);
      expect(client.serverInfo.version, '0.25');
      expect(client.serverInfo.build, 'x');
    });

    test('a rejected hi throws and closes the socket', () async {
      final server = FakeServer();
      final connecting = TinodeClient.withSocket(server.client, config);
      server.ctrl(await server.next('hi'), code: 505);
      await expectLater(
        connecting,
        throwsA(isA<ServerException>().having((e) => e.code, 'code', 505)),
      );
      expect(await server.closedByClient, 1000);
    });
  });

  group('once connected', () {
    late FakeServer server;
    late TinodeClient client;

    setUp(() async {
      server = FakeServer();
      final connecting = TinodeClient.withSocket(server.client, config);
      await server.handshake();
      client = await connecting;
    });

    tearDown(() => client.close());

    group('login', () {
      test('basic sends base64 credentials and keeps the user', () async {
        final result = client.loginBasic('alice', 'alice123');
        final login = await server.next('login');
        expect(login, {
          'id': isA<String>(),
          'scheme': 'basic',
          'secret': base64.encode(utf8.encode('alice:alice123')),
        });
        server.ctrl(
          login,
          params: {'user': 'usrA', 'token': 'tok', 'expires': ts},
        );
        expect(
          await result,
          LoginResult(
            userId: 'usrA',
            token: 'tok',
            expires: DateTime.parse(ts),
          ),
        );
        expect(client.userId, 'usrA');
      });

      test('token sends the token as is', () async {
        final result = client.loginToken('tok/+=');
        final login = await server.next('login');
        expect(login, {
          'id': isA<String>(),
          'scheme': 'token',
          'secret': 'tok/+=',
        });
        server.ctrl(login, params: {'user': 'usrA', 'token': 'tok2'});
        expect(await result, const LoginResult(userId: 'usrA', token: 'tok2'));
        expect(client.userId, 'usrA');
      });

      test('code 300 (credentials to validate) is an error', () async {
        final result = client.loginBasic('alice', 'alice123');
        server.ctrl(
          await server.next('login'),
          code: 300,
          params: {
            'cred': ['email'],
          },
        );
        await expectLater(
          result,
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', 300).having(
              (e) => e.params['cred'],
              'cred',
              ['email'],
            ),
          ),
        );
        expect(client.userId, isNull);
      });

      test('a reply without a token is malformed', () async {
        final result = client.loginToken('tok');
        server.ctrl(await server.next('login'), params: {'user': 'usrA'});
        await expectLater(
          result,
          throwsA(
            isA<MalformedPacketException>().having(
              (e) => e.path,
              'path',
              'ctrl.params.token',
            ),
          ),
        );
        expect(client.userId, isNull);
      });
    });

    group('subscribe', () {
      test('returns the name the server assigned', () async {
        final name = client.subscribe('new');
        final sub = await server.next('sub');
        expect(sub, {'id': isA<String>(), 'topic': 'new'});
        server.ctrl(sub, topic: 'grpX');
        expect(await name, 'grpX');
      });

      test('falls back to the requested name', () async {
        final name = client.subscribe('usrB');
        server.ctrl(await server.next('sub'));
        expect(await name, 'usrB');
      });
    });

    group('leave', () {
      test('detaches but keeps the subscription by default', () async {
        final done = client.leave('grpX');
        final leave = await server.next('leave');
        expect(leave, {'id': isA<String>(), 'topic': 'grpX'});
        server.ctrl(leave);
        await done;
      });

      test('with unsubscribe drops the subscription', () async {
        final done = client.leave('grpX', unsubscribe: true);
        final leave = await server.next('leave');
        expect(leave, {'id': isA<String>(), 'topic': 'grpX', 'unsub': true});
        server.ctrl(leave);
        await done;
      });

      test('a rejected leave throws', () async {
        final done = client.leave('grpX');
        server.ctrl(await server.next('leave'), code: 404);
        await expectLater(done, throwsA(isA<ServerException>()));
      });
    });

    group('getDescription', () {
      test('reads meta.desc', () async {
        final desc = client.getDescription('usrB');
        final get = await server.next('get');
        expect(get, {'id': isA<String>(), 'topic': 'usrB', 'what': 'desc'});
        server.send({
          'meta': {
            'id': get['id'],
            'topic': 'usrB',
            'ts': ts,
            'desc': {
              'seq': 5,
              'public': {'fn': 'Bob'},
            },
          },
        });
        expect(
          await desc,
          const TopicDescription(
            lastSeq: 5,
            public: Profile(name: 'Bob', raw: {'fn': 'Bob'}),
          ),
        );
      });

      test('is null on 204', () async {
        final desc = client.getDescription('usrB');
        server.ctrl(await server.next('get'), code: 204);
        expect(await desc, isNull);
      });
    });

    test('getSubscriptions reads meta, or nothing on 204', () async {
      var subs = client.getSubscriptions('me');
      var get = await server.next('get');
      expect(get, {'id': isA<String>(), 'topic': 'me', 'what': 'sub'});
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
      final chat = (await subs).single;
      expect(chat.topic, 'usrB');
      expect(chat.unread, 2);

      subs = client.getSubscriptions('me');
      get = await server.next('get');
      server.ctrl(get, code: 204);
      expect(await subs, isEmpty);
    });

    group('publish', () {
      test('marks Drafty content and returns the seq', () async {
        final ack = client.publish(
          'usrB',
          const DraftyContent(Drafty(text: 'hi')),
          noEcho: true,
        );
        final pub = await server.next('pub');
        expect(pub, {
          'id': isA<String>(),
          'topic': 'usrB',
          'noecho': true,
          'head': {'mime': 'text/x-drafty'},
          'content': {'txt': 'hi'},
        });
        server.ctrl(pub, code: 202, params: {'seq': 9});
        expect(await ack, PublishResult(seq: 9, time: DateTime.parse(ts)));
      });

      test('sends plain text bare, with echo', () async {
        final ack = client.publish('usrB', const PlainText('hi'));
        final pub = await server.next('pub');
        expect(pub, {'id': isA<String>(), 'topic': 'usrB', 'content': 'hi'});
        server.ctrl(pub, code: 202, params: {'seq': 1});
        expect((await ack).seq, 1);
      });

      test('an ack without seq is malformed', () async {
        final ack = client.publish('usrB', const PlainText('hi'));
        server.ctrl(await server.next('pub'), code: 202);
        await expectLater(
          ack,
          throwsA(
            isA<MalformedPacketException>().having(
              (e) => e.path,
              'path',
              'ctrl.params.seq',
            ),
          ),
        );
      });
    });

    group('getMessages', () {
      test('sends only the given bounds', () async {
        final history = client.getMessages('usrB', before: 10, limit: 5);
        final get = await server.next('get');
        expect(get, {
          'id': isA<String>(),
          'topic': 'usrB',
          'what': 'data',
          'data': {'before': 10, 'limit': 5},
        });
        server.ctrl(get, code: 204);
        expect(await history, isEmpty);
      });

      test('returns the topic history oldest first', () async {
        final history = client.getMessages('usrB', since: 3);
        final get = await server.next('get');
        expect(get['data'], {'since': 3});
        for (final seq in [4, 3]) {
          server.send({
            'data': {'topic': 'usrB', 'seq': seq, 'ts': ts, 'content': '$seq'},
          });
        }
        server.ctrl(get, code: 208);
        expect((await history).map((m) => m.content.text), ['3', '4']);
      });
    });

    test('notes carry no id', () async {
      client
        ..sendTyping('usrB')
        ..markReceived('usrB', 3)
        ..markRead('usrB', 4);
      expect(await server.next('note'), {'topic': 'usrB', 'what': 'kp'});
      expect(await server.next('note'), {
        'topic': 'usrB',
        'what': 'recv',
        'seq': 3,
      });
      expect(await server.next('note'), {
        'topic': 'usrB',
        'what': 'read',
        'seq': 4,
      });
      await server.expectNoMorePackets();
    });

    test('typed streams split unsolicited packets', () async {
      final data = client.messages.toList();
      final info = client.info.toList();
      final presence = client.presence.toList();
      server
        ..send({
          'info': {'topic': 'usrB', 'from': 'usrB', 'what': 'kp'},
        })
        ..send({
          'pres': {'topic': 'me', 'src': 'usrB', 'what': 'on'},
        })
        ..send({
          'data': {'topic': 'usrB', 'seq': 1, 'ts': ts, 'content': 'yo'},
        });
      await Future<void>.delayed(Duration.zero);
      await client.close();
      expect((await data).single.content, const PlainText('yo'));
      expect((await info).single.event, InfoEvent.typing);
      expect((await presence).single.source, 'usrB');
    });
  });
}
