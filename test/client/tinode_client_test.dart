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
      final connecting = TinodeClient.connect(
        connector: (_) async => server.client,
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
      final connecting = TinodeClient.connect(
        config,
        connector: (_) async => server.client,
      );
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
      final connecting = TinodeClient.connect(
        config,
        connector: (_) async => server.client,
      );
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

      test('code 300 asks for credentials to confirm', () async {
        final result = client.loginBasic('alice', 'alice123');
        server.ctrl(
          await server.next('login'),
          code: 300,
          params: {
            'user': 'usrA',
            'token': 'restricted',
            'cred': ['email'],
          },
        );
        await expectLater(
          result,
          throwsA(
            isA<CredentialsRequiredException>()
                .having((e) => e.methods, 'methods', ['email'])
                .having((e) => e.userId, 'userId', 'usrA'),
          ),
        );
        expect(client.userId, isNull);
      });

      test('codes confirm credentials', () async {
        final result = client.loginBasic(
          'alice',
          'alice123',
          codes: const {'email': '123456'},
        );
        final login = await server.next('login');
        expect(login['cred'], [
          {'meth': 'email', 'resp': '123456'},
        ]);
        server.ctrl(login, params: {'user': 'usrA', 'token': 'tok'});
        expect((await result).token, 'tok');

        final again = client.loginToken('tok', codes: const {'email': '1'});
        final token = await server.next('login');
        expect(token['cred'], [
          {'meth': 'email', 'resp': '1'},
        ]);
        server.ctrl(token, params: {'user': 'usrA', 'token': 'tok2'});
        await again;
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

    group('accounts', () {
      String b64(String text) => base64.encode(utf8.encode(text));

      test('createAccount signs up and logs in as the new user', () async {
        final result = client.createAccount(
          login: 'carol',
          password: 'carol123',
          public: const Profile(name: 'Carol'),
          tags: const ['hiking'],
        );
        final acc = await server.next('acc');
        expect(acc, {
          'id': isA<String>(),
          'user': 'new',
          'scheme': 'basic',
          'secret': b64('carol:carol123'),
          'login': true,
          'tags': ['hiking'],
          'desc': {
            'public': {'fn': 'Carol'},
          },
        });
        server.ctrl(acc, params: {'user': 'usrC', 'token': 'tok'});
        expect(await result, const LoginResult(userId: 'usrC', token: 'tok'));
        expect(client.userId, 'usrC');
      });

      test('createAccount with an email asks to confirm it', () async {
        final result = client.createAccount(
          login: 'carol',
          password: 'pw',
          email: 'carol@example.com',
        );
        final acc = await server.next('acc');
        expect(acc['cred'], [
          {'meth': 'email', 'val': 'carol@example.com'},
        ]);
        server.ctrl(
          acc,
          code: 300,
          params: {
            'user': 'usrC',
            'token': 'restricted',
            'cred': ['email'],
          },
        );
        await expectLater(
          result,
          throwsA(
            isA<CredentialsRequiredException>().having(
              (e) => e.methods,
              'methods',
              ['email'],
            ),
          ),
        );
        expect(client.userId, isNull);
      });

      test('createAccount leaves out what is not given', () async {
        final result = client.createAccount(login: 'carol', password: 'pw');
        final acc = await server.next('acc');
        expect(
          acc.keys,
          unorderedEquals(['id', 'user', 'scheme', 'secret', 'login']),
        );
        server.ctrl(acc, params: {'user': 'usrC', 'token': 'tok'});
        await result;
      });

      test('a taken login throws 409 and logs nobody in', () async {
        final result = client.createAccount(login: 'alice', password: 'pw');
        server.ctrl(await server.next('acc'), code: 409);
        await expectLater(
          result,
          throwsA(isA<ServerException>().having((e) => e.code, 'code', 409)),
        );
        expect(client.userId, isNull);
      });

      test(
        'changePassword keeps the login unless a new one is given',
        () async {
          var done = client.changePassword('new-pw');
          var acc = await server.next('acc');
          expect(acc, {
            'id': isA<String>(),
            'scheme': 'basic',
            'secret': b64(':new-pw'),
          });
          server.ctrl(acc);
          await done;

          done = client.changePassword('new-pw', login: 'alicia');
          acc = await server.next('acc');
          expect(acc['secret'], b64('alicia:new-pw'));
          server.ctrl(acc);
          await done;
        },
      );

      test('refuses an empty password or a login with a colon', () {
        expect(() => client.changePassword(''), throwsArgumentError);
        expect(
          () => client.changePassword('pw', login: 'a:b'),
          throwsArgumentError,
        );
        expect(
          () => client.createAccount(login: 'a:b', password: 'pw'),
          throwsArgumentError,
        );
      });

      test('requestPasswordReset takes 301 as started', () async {
        final done = client.requestPasswordReset('alice@example.com');
        final login = await server.next('login');
        expect(login, {
          'id': isA<String>(),
          'scheme': 'reset',
          'secret': b64('basic:email:alice@example.com'),
        });
        server.ctrl(login, code: 301);
        await done;
        expect(client.userId, isNull);
      });

      test('requestPasswordReset passes other refusals on', () async {
        final done = client.requestPasswordReset('alice@example.com');
        server.ctrl(await server.next('login'), code: 400);
        await expectLater(done, throwsA(isA<ServerException>()));
      });

      test('resetPassword sends the code as a one-off login', () async {
        final done = client.resetPassword(
          email: 'alice@example.com',
          code: '123456',
          password: 'new-pw',
        );
        final acc = await server.next('acc');
        expect(acc, {
          'id': isA<String>(),
          'scheme': 'basic',
          'secret': b64(':new-pw'),
          'tmpscheme': 'code',
          'tmpsecret': b64('123456:email:alice@example.com'),
        });
        server.ctrl(acc);
        await done;
        expect(client.userId, isNull);
      });

      test('deleteAccount deletes the user and closes the client', () async {
        final done = client.loginToken('tok');
        server.ctrl(
          await server.next('login'),
          params: {'user': 'usrA', 'token': 'tok'},
        );
        await done;
        final statuses = client.statusChanges.toList();

        final deleted = client.deleteAccount();
        final del = await server.next('del');
        expect(del, {
          'id': isA<String>(),
          'topic': 'me',
          'what': 'user',
          'hard': true,
        });
        server.ctrl(del);
        await deleted;
        expect(client.userId, isNull);
        expect(client.status, const Disconnected());
        expect(await statuses, [const Disconnected()]);
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

      test('retries a locked topic, then gives up', () async {
        final name = client.subscribe('usrB');
        final locked = await server.next('sub');
        server.ctrl(locked, code: 503);
        final retry = await server.next('sub');
        server.ctrl(retry, topic: 'usrB');
        expect(await name, 'usrB');

        final failed = client.subscribe('usrC');
        for (var i = 0; i < 4; i++) {
          server.ctrl(await server.next('sub'), code: 503);
        }
        await expectLater(
          failed,
          throwsA(isA<ServerException>().having((e) => e.code, 'code', 503)),
        );
        await server.expectNoMorePackets();
      });

      test('falls back to the requested name', () async {
        final name = client.subscribe('usrB');
        server.ctrl(await server.next('sub'));
        expect(await name, 'usrB');
      });
    });

    group('createGroup', () {
      test('subscribes to new with its setup, returns the real name', () async {
        final name = client.createGroup(
          public: const Profile(name: 'Hikers'),
          tags: const ['hiking'],
        );
        final sub = await server.next('sub');
        expect(sub, {
          'id': isA<String>(),
          'topic': 'new',
          'set': {
            'desc': {
              'public': {'fn': 'Hikers'},
            },
            'tags': ['hiking'],
          },
        });
        server.ctrl(sub, topic: 'grpX');
        expect(await name, 'grpX');
      });

      test('a channel subscribes to nch; no setup sends none', () async {
        final name = client.createGroup(channel: true);
        final sub = await server.next('sub');
        expect(sub, {
          'id': isA<String>(),
          'topic': 'nch',
          'set': <String, Object?>{},
        });
        server.ctrl(sub, topic: 'chnX');
        expect(await name, 'chnX');
      });
    });

    group('find', () {
      Json results(Json get, List<Json> found) => {
        'meta': {'id': get['id'], 'topic': 'fnd', 'ts': ts, 'sub': found},
      };

      test('attaches fnd once, sets the query, reads the results', () async {
        var found = client.find('basic:bob');
        final sub = await server.next('sub');
        expect(sub, {'id': isA<String>(), 'topic': 'fnd'});
        server.ctrl(sub, topic: 'fnd');
        final set = await server.next('set');
        expect(set, {
          'id': isA<String>(),
          'topic': 'fnd',
          'desc': {'public': 'basic:bob'},
        });
        server.ctrl(set);
        final get = await server.next('get');
        expect(get, {'id': isA<String>(), 'topic': 'fnd', 'what': 'sub'});
        server.send(
          results(get, [
            {
              'topic': 'usrB',
              'public': {'fn': 'Bob'},
            },
          ]),
        );
        expect((await found).single.topic, 'usrB');

        found = client.find('nobody');
        server.ctrl(await server.next('set'));
        final empty = await server.next('get');
        server.ctrl(empty, code: 204);
        expect(await found, isEmpty);
        await server.expectNoMorePackets();
      });

      test('searches take turns', () async {
        final first = client.find('a');
        final second = client.find('b');
        server.ctrl(await server.next('sub'), topic: 'fnd');
        final setA = await server.next('set');
        expect(setA['desc'], {'public': 'a'});
        server.ctrl(setA);
        final getA = await server.next('get');
        // The second query must wait until the first has its results.
        await server.expectNoMorePackets();
        server.send(
          results(getA, [
            {'topic': 'usrA'},
          ]),
        );
        final setB = await server.next('set');
        expect(setB['desc'], {'public': 'b'});
        server.ctrl(setB);
        final getB = await server.next('get');
        server.send(
          results(getB, [
            {'topic': 'usrB'},
          ]),
        );
        expect((await first).single.topic, 'usrA');
        expect((await second).single.topic, 'usrB');
      });

      test('a failed search does not block the next', () async {
        final failed = client.find('a');
        server.ctrl(await server.next('sub'), code: 403);
        await expectLater(failed, throwsA(isA<ServerException>()));

        final found = client.find('b');
        server.ctrl(await server.next('sub'), topic: 'fnd');
        final set = await server.next('set');
        server.ctrl(set);
        final empty = await server.next('get');
        server.ctrl(empty, code: 204);
        expect(await found, isEmpty);
      });

      test('refuses a blank query', () {
        expect(() => client.find('  '), throwsArgumentError);
      });
    });

    group('set', () {
      test('setSubscription adds a member and returns their access', () async {
        final access = client.setSubscription(
          'grpX',
          userId: 'usrB',
          mode: AccessMode.parse('JRWP'),
        );
        final set = await server.next('set');
        expect(set, {
          'id': isA<String>(),
          'topic': 'grpX',
          'sub': {'user': 'usrB', 'mode': 'JRWP'},
        });
        server.ctrl(
          set,
          params: {
            'acs': {'want': 'JRWPS', 'given': 'JRWP', 'mode': 'JRWP'},
            'user': 'usrB',
          },
        );
        expect((await access)?.given, AccessMode.parse('JRWP'));
      });

      test(
        'setSubscription without a user or mode sends an empty sub',
        () async {
          final access = client.setSubscription('grpX');
          final set = await server.next('set');
          expect(set['sub'], <String, Object?>{});
          server.ctrl(set);
          expect(await access, isNull);
        },
      );

      test('a refused invite throws', () async {
        final access = client.setSubscription('grpX', userId: 'usrB');
        server.ctrl(await server.next('set'), code: 403);
        await expectLater(access, throwsA(isA<ServerException>()));
      });

      test('setDescription sends only what changes', () async {
        final done = client.setDescription(
          'grpX',
          public: const Profile(name: 'Hikers'),
          defaultAccess: DefaultAccess(
            auth: AccessMode.parse('JRWP'),
            anon: AccessMode.none,
          ),
        );
        final set = await server.next('set');
        expect(set, {
          'id': isA<String>(),
          'topic': 'grpX',
          'desc': {
            'public': {'fn': 'Hikers'},
            'defacs': {'auth': 'JRWP', 'anon': 'N'},
          },
        });
        server.ctrl(set);
        await done;
        expect(() => client.setDescription('grpX'), throwsArgumentError);
      });

      test('setTags replaces the tags', () async {
        final done = client.setTags('me', const ['basic:alice', 'hiking']);
        final set = await server.next('set');
        expect(set, {
          'id': isA<String>(),
          'topic': 'me',
          'tags': ['basic:alice', 'hiking'],
        });
        server.ctrl(set);
        await done;
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

    test('getSubscriptions reads one member, or none on 204', () async {
      var subs = client.getSubscriptions('grpX', userId: 'usrB');
      var get = await server.next('get');
      expect(get, {
        'id': isA<String>(),
        'topic': 'grpX',
        'what': 'sub',
        'sub': {'user': 'usrB'},
      });
      server.send({
        'meta': {
          'id': get['id'],
          'topic': 'grpX',
          'ts': ts,
          'sub': [
            {'user': 'usrB', 'read': 4, 'recv': 6},
          ],
        },
      });
      final member = (await subs).single;
      expect((member.userId, member.read, member.received), ('usrB', 4, 6));

      subs = client.getSubscriptions('grpX', userId: 'usrC');
      get = await server.next('get');
      server.ctrl(get, code: 204);
      expect(await subs, isEmpty);
    });

    group('if modified since', () {
      final since = DateTime.utc(2026, 10, 1, 8, 30, 0, 250);

      test('getDescription sends ims', () async {
        final desc = client.getDescription('usrB', ifModifiedSince: since);
        final get = await server.next('get');
        expect(get, {
          'id': isA<String>(),
          'topic': 'usrB',
          'what': 'desc',
          'desc': {'ims': '2026-10-01T08:30:00.250Z'},
        });
        server.ctrl(get, code: 204);
        expect(await desc, isNull);
      });

      test('getSubscriptions sends ims and limit', () async {
        final subs = client.getSubscriptions(
          'me',
          ifModifiedSince: since,
          limit: 10,
        );
        final get = await server.next('get');
        expect(get['sub'], {'ims': '2026-10-01T08:30:00.250Z', 'limit': 10});
        server.ctrl(get, code: 204);
        expect(await subs, isEmpty);
      });

      test('nothing modified gives no subscriptions', () async {
        final subs = client.getSubscriptions('me', ifModifiedSince: since);
        server.ctrl(await server.next('get'), code: 304);
        expect(await subs, isEmpty);
      });

      test('other errors still throw', () async {
        final subs = client.getSubscriptions('me', ifModifiedSince: since);
        server.ctrl(await server.next('get'), code: 403);
        await expectLater(
          subs,
          throwsA(isA<ServerException>().having((e) => e.code, 'code', 403)),
        );
      });
    });

    group('getDeleteLog', () {
      test('sends the bounds and reads meta.del', () async {
        final log = client.getDeleteLog('usrB', since: 3, limit: 8);
        final get = await server.next('get');
        expect(get, {
          'id': isA<String>(),
          'topic': 'usrB',
          'what': 'del',
          'del': {'since': 3, 'limit': 8},
        });
        server.send({
          'meta': {
            'id': get['id'],
            'topic': 'usrB',
            'ts': ts,
            'del': {
              'clear': 4,
              'delseq': [
                {'low': 2, 'hi': 4},
              ],
            },
          },
        });
        expect(
          await log,
          const DeleteLog(lastDeleteId: 4, ranges: [SeqRange(2, 4)]),
        );
      });

      test('is empty on 204', () async {
        final log = client.getDeleteLog('usrB');
        final get = await server.next('get');
        expect(get, {'id': isA<String>(), 'topic': 'usrB', 'what': 'del'});
        server.ctrl(get, code: 204);
        expect(await log, DeleteLog.empty);
      });
    });

    group('deleteMessages', () {
      test('sends the ranges and returns the delete ID', () async {
        final deleted = client.deleteMessages('usrB', const [
          SeqRange.single(3),
          SeqRange(5, 9),
        ]);
        final del = await server.next('del');
        expect(del, {
          'id': isA<String>(),
          'topic': 'usrB',
          'what': 'msg',
          'delseq': [
            {'low': 3},
            {'low': 5, 'hi': 9},
          ],
        });
        server.ctrl(del, params: {'del': 7});
        expect(await deleted, 7);
      });

      test('hard deletes for everyone', () async {
        final deleted = client.deleteMessages('usrB', const [
          SeqRange.single(3),
        ], hard: true);
        final del = await server.next('del');
        expect(del['hard'], isTrue);
        server.ctrl(del, params: {'del': 1});
        expect(await deleted, 1);
      });

      test('refuses an empty list', () {
        expect(
          () => client.deleteMessages('usrB', const []),
          throwsArgumentError,
        );
      });
    });

    group('deleteTopic', () {
      test('hard deletes the topic', () async {
        final done = client.deleteTopic('grpX');
        final del = await server.next('del');
        expect(del, {
          'id': isA<String>(),
          'topic': 'grpX',
          'what': 'topic',
          'hard': true,
        });
        server.ctrl(del);
        await done;
      });

      test('a refusal throws', () async {
        final done = client.deleteTopic('grpX');
        server.ctrl(await server.next('del'), code: 403);
        await expectLater(done, throwsA(isA<ServerException>()));
      });
    });

    group('deleteSubscription', () {
      test('removes the member', () async {
        final done = client.deleteSubscription('grpX', userId: 'usrB');
        final del = await server.next('del');
        expect(del, {
          'id': isA<String>(),
          'topic': 'grpX',
          'what': 'sub',
          'user': 'usrB',
        });
        server.ctrl(del);
        await done;
      });

      test('someone who is not a member (304) counts as removed', () async {
        final done = client.deleteSubscription('grpX', userId: 'usrB');
        server.ctrl(await server.next('del'), code: 304);
        await done;
      });

      test('other refusals throw', () async {
        final done = client.deleteSubscription('grpX', userId: 'usrB');
        server.ctrl(await server.next('del'), code: 409);
        await expectLater(
          done,
          throwsA(isA<ServerException>().having((e) => e.code, 'code', 409)),
        );
      });
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

      test('adds the given head to the Drafty mime', () async {
        final ack = client.publish(
          'usrB',
          const DraftyContent(Drafty(text: 'hi')),
          head: {'x-app-cid': 'abc'},
        );
        final pub = await server.next('pub');
        expect(pub['head'], {'mime': 'text/x-drafty', 'x-app-cid': 'abc'});
        server.ctrl(pub, code: 202, params: {'seq': 2});
        expect((await ack).seq, 2);
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

    group('startCall', () {
      test('publishes a call message and returns its seq', () async {
        final ack = client.startCall('usrB');
        final pub = await server.next('pub');
        expect(pub, {
          'id': isA<String>(),
          'topic': 'usrB',
          'head': {'mime': 'text/x-drafty', 'webrtc': 'started'},
          'content': {
            'txt': ' ',
            'fmt': [
              {'len': 1},
            ],
            'ent': [
              {'tp': 'VC'},
            ],
          },
        });
        server.ctrl(pub, code: 202, params: {'seq': 12});
        expect((await ack).seq, 12);
      });

      test('marks an audio-only call in head and content', () async {
        final ack = client.startCall('usrB', audioOnly: true);
        final pub = await server.next('pub');
        expect(pub['head'], {
          'mime': 'text/x-drafty',
          'webrtc': 'started',
          'aonly': true,
        });
        expect(
          MessageContent.fromJson(pub['content']),
          DraftyContent(Drafty.videoCall(audioOnly: true)),
        );
        server.ctrl(pub, code: 202, params: {'seq': 1});
        await ack;
      });

      test('a chat already in a call is busy (486)', () async {
        final ack = client.startCall('usrB');
        server.ctrl(await server.next('pub'), code: 486);
        await expectLater(
          ack,
          throwsA(isA<ServerException>().having((e) => e.code, 'code', 486)),
        );
      });
    });

    group('sendCallEvent', () {
      test('sends a call note, with a payload when given', () async {
        client
          ..sendCallEvent('usrB', 12, CallEvent.ringing)
          ..sendCallEvent(
            'usrB',
            12,
            CallEvent.offer,
            payload: const CallDescription(type: 'offer', sdp: 'v=0').toJson(),
          )
          ..sendCallEvent('usrB', 12, CallEvent.iceCandidate, payload: {});
        expect(await server.next('note'), {
          'topic': 'usrB',
          'what': 'call',
          'seq': 12,
          'event': 'ringing',
        });
        expect(await server.next('note'), {
          'topic': 'usrB',
          'what': 'call',
          'seq': 12,
          'event': 'offer',
          'payload': {'type': 'offer', 'sdp': 'v=0'},
        });
        expect((await server.next('note'))['event'], 'ice-candidate');
        await server.expectNoMorePackets();
      });

      test('refuses what the server would drop', () async {
        expect(
          () => client.sendCallEvent('usrB', 12, CallEvent.unknown),
          throwsArgumentError,
        );
        expect(
          () => client.sendCallEvent('usrB', 0, CallEvent.accept),
          throwsArgumentError,
        );
        await server.expectNoMorePackets();
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
