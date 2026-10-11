import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import '../support/fake_server.dart';

final config = TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'key',
  userAgent: 'test/1.0',
  language: 'en-US',
  platform: DevicePlatform.android,
  reconnect: const ReconnectPolicy(
    base: Duration(milliseconds: 1),
    cap: Duration(milliseconds: 4),
  ),
  probeAfter: null,
);

void main() {
  late FakeConnector connector;
  late FakeServer server;
  late TinodeClient client;
  late StreamQueue<ConnectionStatus> statuses;

  Future<void> connect() async {
    final connecting = TinodeClient.connect(config, connector: connector.call);
    server = await connector.next();
    await server.handshake();
    client = await connecting;
    statuses = StreamQueue(client.statusChanges);
  }

  Future<void> login() async {
    final done = client.loginToken('start');
    server.ctrl(
      await server.next('login'),
      params: {'user': 'usrA', 'token': 'tok'},
    );
    await done;
  }

  /// Expects the `hi` that registers [dev] mid-session, and answers it.
  Future<void> expectUpdate(String dev) async {
    final hi = await server.next('hi');
    expect(hi, {
      'id': isA<String>(),
      'ver': TinodeClient.protocolVersion,
      'ua': 'test/1.0',
      'lang': 'en-US',
      'dev': dev,
      'platf': 'android',
    });
    server.ctrl(hi);
  }

  setUp(() => connector = FakeConnector());

  tearDown(() => client.close());

  test('hi carries the platform, and no device before one is set', () async {
    final connecting = TinodeClient.connect(config, connector: connector.call);
    server = await connector.next();
    final hi = await server.next('hi');
    expect(hi, {
      'id': isA<String>(),
      'ver': TinodeClient.protocolVersion,
      'ua': 'test/1.0',
      'lang': 'en-US',
      'platf': 'android',
    });
    server.ctrl(hi, code: 201, params: {'ver': '0.25'});
    client = await connecting;
  });

  test('a token set while logged in is sent at once', () async {
    await connect();
    await login();

    final set = client.setDeviceToken('fcm1');
    await expectUpdate('fcm1');
    await set;
  });

  test('null removes the token, and an unchanged one sends nothing', () async {
    await connect();
    await login();
    final set = client.setDeviceToken('fcm1');
    await expectUpdate('fcm1');
    await set;

    await client.setDeviceToken('fcm1');
    await server.expectNoMorePackets();

    final cleared = client.setDeviceToken(null);
    await expectUpdate('␡');
    await cleared;
  });

  test('a refusal while logged in throws', () async {
    await connect();
    await login();
    final set = client.setDeviceToken('fcm1');
    server.ctrl(await server.next('hi'), code: 500);
    await expectLater(set, throwsA(isA<ServerException>()));
  });

  test('a token set before login is sent once a login succeeds', () async {
    await connect();
    await client.setDeviceToken('fcm1');
    await server.expectNoMorePackets();

    final done = client.loginBasic('alice', 'alice123');
    server.ctrl(
      await server.next('login'),
      params: {'user': 'usrA', 'token': 'tok'},
    );
    await expectUpdate('fcm1');
    expect((await done).userId, 'usrA');
  });

  test('a refused update after login keeps the login', () async {
    await connect();
    await client.setDeviceToken('fcm1');
    final done = client.loginToken('start');
    server
      ..ctrl(
        await server.next('login'),
        params: {'user': 'usrA', 'token': 'tok'},
      )
      ..ctrl(await server.next('hi'), code: 500);
    expect((await done).token, 'tok');
  });

  test('a token set while not connected only waits', () async {
    await connect();
    await login();
    await server.close();
    expect(await statuses.next, isA<Reconnecting>());

    await client.setDeviceToken('fcm1');
    server = await connector.next();
    final hi = await server.next('hi');
    expect(hi['dev'], 'fcm1');
  });

  test('every reconnect says hi with the token, then sends no more', () async {
    await connect();
    await login();
    final set = client.setDeviceToken('fcm1');
    await expectUpdate('fcm1');
    await set;

    await server.close();
    expect(await statuses.next, isA<Reconnecting>());
    server = await connector.next();
    final hi = await server.next('hi');
    expect(hi['dev'], 'fcm1');
    expect(hi['platf'], 'android');
    server
      ..ctrl(hi, code: 201, params: {'ver': '0.25'})
      ..ctrl(
        await server.next('login'),
        params: {'user': 'usrA', 'token': 'tok2'},
      );
    expect(await statuses.next, isA<Connected>());
    await server.expectNoMorePackets();
  });

  test('restore says hi with a token set right after it', () async {
    client = TinodeClient.restore(
      config,
      token: 'tok',
      connector: connector.call,
    );
    statuses = StreamQueue(client.statusChanges);
    await client.setDeviceToken('fcm1');

    server = await connector.next();
    final hi = await server.next('hi');
    expect(hi['dev'], 'fcm1');
    server
      ..ctrl(hi, code: 201, params: {'ver': '0.25'})
      ..ctrl(
        await server.next('login'),
        params: {'user': 'usrA', 'token': 'tok2'},
      );
    expect(await statuses.next, isA<Connected>());
    await server.expectNoMorePackets();
  });
}
