@Tags(['integration'])
library;

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';
import 'package:web_socket/web_socket.dart';

// Runs against ../tinode-tests (sample users alice and bob).
TinodeConfig configWith({Duration? probeAfter}) => TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
  userAgent: 'tinode_dart_client-test/0.1',
  reconnect: const ReconnectPolicy(
    base: Duration(milliseconds: 50),
    cap: Duration(milliseconds: 200),
  ),
  probeAfter: probeAfter,
  probeTimeout: const Duration(seconds: 2),
);

/// Real sockets, with a way to cut the current one from the client side.
final class SeverableConnector {
  late WebSocket _current;
  int connects = 0;

  Future<WebSocket> call(Uri uri) async {
    connects++;
    return _current = await WebSocket.connect(uri);
  }

  Future<void> sever() => _current.close();
}

void main() {
  test('a severed session comes back and catches up by seq', () async {
    final connector = SeverableConnector();
    final alice = await TinodeClient.connect(
      configWith(),
      connector: connector.call,
    );
    addTearDown(alice.close);
    final bob = await TinodeClient.connect(configWith());
    addTearDown(bob.close);

    final aliceLogin = await alice.loginBasic('alice', 'alice123');
    final bobLogin = await bob.loginBasic('bob', 'bob123');
    final chat = await alice.subscribe(bobLogin.userId);
    await bob.subscribe(aliceLogin.userId);
    final before = await bob.publish(aliceLogin.userId, const PlainText('a'));

    final statuses = StreamQueue(alice.statusChanges);
    await connector.sever();
    expect(await statuses.next, isA<Reconnecting>());

    // Sent while alice is down: it reaches her only through history.
    final missed = await bob.publish(aliceLogin.userId, const PlainText('b'));

    final back = await statuses.next;
    expect(back, isA<Connected>());
    final relogin = (back as Connected).login!;
    expect(relogin.userId, aliceLogin.userId);
    expect(
      relogin.expires!.isBefore(aliceLogin.expires!),
      isFalse,
      reason: 'a login renews the expiry',
    );
    expect(back.lostTopics, isEmpty);
    expect(connector.connects, 2);

    final gap = await alice.getMessages(chat, since: before.seq + 1);
    expect(gap.map((m) => m.seq), [missed.seq]);

    // Re-attached: live traffic flows again without a new subscribe.
    final live = alice.messages.firstWhere((m) => m.topic == chat);
    final after = await bob.publish(aliceLogin.userId, const PlainText('c'));
    expect((await live).seq, after.seq);
  });

  test('the server answers probes, so a quiet link stays up', () async {
    final client = await TinodeClient.connect(
      configWith(probeAfter: const Duration(milliseconds: 200)),
    );
    addTearDown(client.close);
    final statuses = <ConnectionStatus>[];
    client.statusChanges.listen(statuses.add);
    await client.loginBasic('alice', 'alice123');

    // Several probe rounds, each well within the probe timeout.
    await Future<void>.delayed(const Duration(seconds: 1));
    client.resume();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(statuses, isEmpty);
    expect(client.status, const Connected());
  });

  test('an unreachable server throws ServerUnreachableException', () async {
    final config = TinodeConfig(
      server: Uri.parse('ws://localhost:1'),
      apiKey: 'key',
      userAgent: 'test/1.0',
    );
    await expectLater(
      TinodeClient.connect(config),
      throwsA(isA<ServerUnreachableException>()),
    );
  });
}
