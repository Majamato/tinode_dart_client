import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import '../support/fake_server.dart';

TinodeConfig configWith({
  ReconnectPolicy reconnect = const ReconnectPolicy(
    base: Duration(milliseconds: 1),
    cap: Duration(milliseconds: 4),
  ),
  Duration? probeAfter,
  Duration probeTimeout = const Duration(milliseconds: 50),
}) => TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'key',
  userAgent: 'test/1.0',
  reconnect: reconnect,
  probeAfter: probeAfter,
  probeTimeout: probeTimeout,
);

Matcher reconnecting(int attempt, {Matcher cause = anything}) =>
    isA<Reconnecting>()
        .having((s) => s.attempt, 'attempt', attempt)
        .having((s) => s.cause, 'cause', cause);

void main() {
  late FakeConnector connector;
  late FakeServer server;
  late TinodeClient client;
  late StreamQueue<ConnectionStatus> statuses;

  Future<void> connect([TinodeConfig? config]) async {
    final connecting = TinodeClient.connect(
      config ?? configWith(),
      connector: connector.call,
    );
    server = await connector.next();
    await server.handshake();
    client = await connecting;
    statuses = StreamQueue(client.statusChanges);
  }

  Future<void> login(String token) async {
    final done = client.loginToken('start');
    server.ctrl(
      await server.next('login'),
      params: {'user': 'usrA', 'token': token},
    );
    await done;
  }

  Future<void> attach(String topic) async {
    final done = client.subscribe(topic);
    server.ctrl(await server.next('sub'));
    await done;
  }

  /// Severs the socket and answers the reconnect's `hi`.
  Future<void> drop() async {
    await server.close();
    expect(await statuses.next, isA<Reconnecting>());
    server = await connector.next();
    await server.handshake();
  }

  setUp(() => connector = FakeConnector());

  tearDown(() => client.close());

  test(
    'restores the session: hi, token login, me first, then the rest',
    () async {
      await connect();
      await login('tok1');
      await attach('usrB');
      await attach('me');

      await drop();
      final login2 = await server.next('login');
      expect(login2, {
        'id': isA<String>(),
        'scheme': 'token',
        'secret': 'tok1',
      });
      server.ctrl(login2, params: {'user': 'usrA', 'token': 'tok2'});
      for (final topic in ['me', 'usrB']) {
        final sub = await server.next('sub');
        expect(sub['topic'], topic);
        server.ctrl(sub);
      }
      expect(
        await statuses.next,
        const Connected(
          login: LoginResult(userId: 'usrA', token: 'tok2'),
        ),
      );
      await server.expectNoMorePackets();
    },
  );

  test('logs in with the newest token on the next reconnect', () async {
    await connect();
    await login('tok1');

    await drop();
    final relogin = await server.next('login');
    server.ctrl(relogin, params: {'user': 'usrA', 'token': 'tok2'});
    await statuses.next;

    await drop();
    expect((await server.next('login'))['secret'], 'tok2');
  });

  test('requests fail fast while down, notes are dropped', () async {
    await connect();
    await server.close();
    await statuses.next;
    await expectLater(
      client.subscribe('usrB'),
      throwsA(isA<ConnectionClosedException>()),
    );
    client.sendTyping('usrB');
    await server.expectNoMorePackets();
    expect(client.status, isA<Reconnecting>());
  });

  test('call events fail fast while down, not dropped', () async {
    await connect();
    client.suspend();
    expect(await statuses.next, const Suspended());
    expect(
      () => client.sendCallEvent('usrB', 5, CallEvent.hangUp),
      throwsA(isA<ConnectionClosedException>()),
    );
  });

  test('a drop fails the requests waiting for replies', () async {
    await connect();
    final ack = client.publish('usrB', const PlainText('hi'));
    await server.next('pub');
    await server.close();
    await expectLater(ack, throwsA(isA<ConnectionClosedException>()));
  });

  test('a refused token is final', () async {
    await connect();
    await login('tok1');
    final events = client.events.toList();

    await drop();
    server.ctrl(await server.next('login'), code: 401);
    expect(
      await statuses.next,
      isA<Disconnected>().having(
        (s) => s.cause,
        'cause',
        isA<ServerException>().having((e) => e.code, 'code', 401),
      ),
    );
    expect(await statuses.hasNext, isFalse);
    expect(await events, isEmpty);
    await connector.expectNoConnect();
  });

  test('topics the server refuses are reported lost and forgotten', () async {
    await connect();
    await attach('grpX');

    await drop();
    server.ctrl(await server.next('sub'), code: 403);
    expect(
      await statuses.next,
      isA<Connected>().having(
        (s) => s.lostTopics['grpX']?.code,
        'grpX refusal',
        403,
      ),
    );

    await drop();
    expect(await statuses.next, const Connected());
    await server.expectNoMorePackets();
  });

  test('an unreachable server is retried with growing attempts', () async {
    await connect();
    connector.refuse = 2;
    await server.close();
    expect(await statuses.next, reconnecting(1));
    for (final attempt in [2, 3]) {
      expect(
        await statuses.next,
        reconnecting(attempt, cause: isA<ServerUnreachableException>()),
      );
    }
    server = await connector.next();
    await server.handshake();
    expect(await statuses.next, const Connected());
    expect(connector.connects, 4);

    // A recovered link counts its attempts from 1 again.
    await server.close();
    expect(await statuses.next, reconnecting(1));
  });

  test('a failed hi is retried; a 505 one is final', () async {
    await connect();
    await server.close();
    await statuses.next;
    server = await connector.next();
    server.ctrl(await server.next('hi'), code: 503);
    expect(await statuses.next, reconnecting(2, cause: isA<ServerException>()));
    server = await connector.next();
    server.ctrl(await server.next('hi'), code: 505);
    expect(await statuses.next, isA<Disconnected>());
  });

  test('leaving while down forgets the topic; unsubscribing fails', () async {
    await connect();
    await attach('usrB');
    await attach('usrC');
    await server.close();
    await statuses.next;

    await client.leave('usrB');
    await expectLater(
      client.leave('usrC', unsubscribe: true),
      throwsA(isA<ConnectionClosedException>()),
    );
    server = await connector.next();
    await server.handshake();
    expect(await statuses.next, const Connected());
    await server.expectNoMorePackets();
  });

  test('event listeners survive a reconnect', () async {
    await connect();
    final messages = StreamQueue(client.messages);
    await drop();
    await statuses.next;
    server.send({
      'data': {'topic': 'usrB', 'seq': 7, 'ts': ts, 'content': 'back'},
    });
    expect((await messages.next).seq, 7);
  });

  group('suspend and resume', () {
    test('suspend closes the socket and waits for resume', () async {
      await connect();
      await attach('me');

      client.suspend();
      expect(await statuses.next, const Suspended());
      expect(await server.closedByClient, 1000);
      await connector.expectNoConnect();

      client.resume();
      expect(
        await statuses.next,
        isA<Reconnecting>()
            .having((s) => s.attempt, 'attempt', 1)
            .having((s) => s.retryIn, 'retryIn', Duration.zero),
      );
      server = await connector.next();
      await server.handshake();
      server.ctrl(await server.next('sub'));
      expect(await statuses.next, const Connected());
    });

    test('resume during a backoff wait tries at once', () async {
      await connect(
        configWith(
          reconnect: const ReconnectPolicy(
            base: Duration(hours: 1),
            cap: Duration(hours: 1),
          ),
        ),
      );
      await server.close();
      await statuses.next;
      client.resume();
      expect(await statuses.next, reconnecting(2));
      server = await connector.next();
      await server.handshake();
      expect(await statuses.next, const Connected());
    });

    test('suspend overtakes a reconnect in progress', () async {
      await connect();
      await server.close();
      await statuses.next;
      server = await connector.next();
      await server.next('hi');
      client.suspend();
      expect(await statuses.next, const Suspended());
      expect(await server.closedByClient, 1000);
      await connector.expectNoConnect();
    });
  });

  group('probing', () {
    test('resume can probe with a shorter deadline', () async {
      await connect(configWith(probeTimeout: const Duration(seconds: 5)));
      client.resume(probeTimeout: const Duration(milliseconds: 20));
      await server.probed();
      expect(
        await statuses.next.timeout(const Duration(milliseconds: 500)),
        reconnecting(1),
      );
    });

    test('resume probes a live socket; an answer keeps it', () async {
      await connect();
      client.resume();
      await server.probed();
      server.sendRaw('0');
      await connector.expectNoConnect(wait: const Duration(milliseconds: 100));
      expect(client.status, const Connected());
    });

    test('an unanswered probe drops the socket', () async {
      await connect();
      client.resume();
      await server.probed();
      expect(
        await statuses.next,
        reconnecting(
          1,
          cause: isA<ConnectionClosedException>().having(
            (e) => e.reason,
            'reason',
            'probe unanswered',
          ),
        ),
      );
    });

    test('silence beyond probeAfter sends a probe on its own', () async {
      await connect(configWith(probeAfter: const Duration(milliseconds: 20)));
      await server.probed();
      server.sendRaw('0');
      await server.probed(2);
    });
  });

  test('close is final and never reconnects', () async {
    await connect();
    await client.close();
    expect(await statuses.next, const Disconnected());
    expect(await statuses.hasNext, isFalse);
    await connector.expectNoConnect();
  });

  test('with reconnect disabled a drop is final', () async {
    await connect(configWith(reconnect: const ReconnectPolicy.disabled()));
    await server.close();
    expect(
      await statuses.next,
      isA<Disconnected>().having(
        (s) => s.cause,
        'cause',
        isA<ConnectionClosedException>(),
      ),
    );
    await connector.expectNoConnect();
  });

  group('restore', () {
    void restore(String token) {
      client = TinodeClient.restore(
        configWith(),
        token: token,
        connector: connector.call,
      );
      statuses = StreamQueue(client.statusChanges);
    }

    test('starts offline and fails requests fast', () async {
      connector.refuse = 100;
      restore('tok1');
      expect(client.status, reconnecting(1));
      expect(client.serverInfo, ServerInfo.unknown);
      expect(client.serverInfo.callsEnabled, isFalse);
      expect(client.userId, isNull);
      await expectLater(
        client.getSubscriptions('me'),
        throwsA(isA<ConnectionClosedException>()),
      );
      expect(
        await statuses.next,
        reconnecting(2, cause: isA<ServerUnreachableException>()),
      );
    });

    test('once the server answers it logs in with the token', () async {
      connector.refuse = 2;
      restore('tok1');
      server = await connector.next();
      final hi = await server.next('hi');
      server.ctrl(hi, code: 201, params: {'ver': '0.25', 'build': 'b'});
      final login = await server.next('login');
      expect(login['scheme'], 'token');
      expect(login['secret'], 'tok1');
      server.ctrl(login, params: {'user': 'usrA', 'token': 'tok2'});

      final connected = await statuses.take(3).then((s) => s.last as Connected);
      expect(connected.login?.token, 'tok2');
      expect(client.userId, 'usrA');
      expect(client.serverInfo.build, 'b');
      expect(client.status, isA<Connected>());
    });

    test('a refused token is final', () async {
      restore('expired');
      server = await connector.next();
      await server.handshake();
      server.ctrl(await server.next('login'), code: 401);
      expect(
        await statuses.next,
        isA<Disconnected>().having(
          (s) => s.cause,
          'cause',
          isA<ServerException>().having((e) => e.code, 'code', 401),
        ),
      );
      await connector.expectNoConnect();
    });
  });
}
