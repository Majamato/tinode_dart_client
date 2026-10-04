@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against ../tinode-tests (sample users alice and bob).
final config = TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
  userAgent: 'tinode_dart_client-test/0.1',
);

Future<(TinodeClient, LoginResult)> loginAs(String user) async {
  final client = await TinodeClient.connect(config);
  addTearDown(client.close);
  return (client, await client.loginBasic(user, '${user}123'));
}

void main() {
  test('alice and bob chat end to end', () async {
    final (alice, aliceLogin) = await loginAs('alice');
    final (bob, bobLogin) = await loginAs('bob');
    expect(alice.serverInfo.version, isNotEmpty);

    await alice.subscribe('me');
    final chats = await alice.getSubscriptions('me');
    expect(chats.map((s) => s.topic), contains(bobLogin.userId));

    // In P2P each side names the topic after the peer.
    await alice.subscribe(bobLogin.userId);
    await bob.subscribe(aliceLogin.userId);
    final desc = await alice.getDescription(bobLogin.userId);
    expect(desc?.public?.name, isNotNull);

    final text = 'integration ${DateTime.now().toIso8601String()}';
    final received = bob.messages.firstWhere((m) => m.content.text == text);
    final ack = await alice.publish(bobLogin.userId, PlainText(text));
    final message = await received;
    expect(message.seq, ack.seq);
    expect(message.from, aliceLogin.userId);

    final history = await alice.getMessages(bobLogin.userId, limit: 3);
    expect(history.last.seq, ack.seq);
    final seqs = [for (final m in history) m.seq];
    expect(seqs, [...seqs]..sort());

    final read = alice.info.firstWhere((i) => i.event == InfoEvent.read);
    bob.markRead(aliceLogin.userId, ack.seq);
    expect((await read).seq, ack.seq);

    await alice.leave(bobLogin.userId);
  });

  test('a token from basic login opens a new session', () async {
    final (_, login) = await loginAs('alice');
    final client = await TinodeClient.connect(config);
    addTearDown(client.close);
    expect((await client.loginToken(login.token)).userId, login.userId);
  });

  test('a wrong password is a ServerException', () async {
    final client = await TinodeClient.connect(config);
    addTearDown(client.close);
    await expectLater(
      client.loginBasic('alice', 'nope'),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 401)),
    );
  });
}
