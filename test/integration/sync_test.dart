@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against ../tinode-tests (sample users alice and bob). Asserts only on
// what each test sends itself, since earlier runs leave history behind.
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

String unique(String what) => '$what ${DateTime.now().microsecondsSinceEpoch}';

void main() {
  late TinodeClient alice;
  late TinodeClient bob;
  late String aliceId;
  late String bobId;

  setUp(() async {
    final (a, aliceLogin) = await loginAs('alice');
    final (b, bobLogin) = await loginAs('bob');
    alice = a;
    bob = b;
    aliceId = aliceLogin.userId;
    bobId = bobLogin.userId;
    await alice.subscribe(bobId);
    await bob.subscribe(aliceId);
  });

  test('an app head key comes back on the copy and in history', () async {
    final text = unique('cid');
    final received = bob.messages.firstWhere((m) => m.content.text == text);
    final ack = await alice.publish(
      bobId,
      PlainText(text),
      head: {'x-tinode-test-cid': 'cid-123'},
    );
    expect((await received).head?.raw['x-tinode-test-cid'], 'cid-123');

    final history = await alice.getMessages(bobId, since: ack.seq);
    expect(history.single.head?.raw['x-tinode-test-cid'], 'cid-123');
  });

  test('a soft delete hides a message for the deleter only', () async {
    final before = (await alice.getDescription(bobId))!.lastDeleteId;
    final ack = await alice.publish(bobId, PlainText(unique('soft')));

    final deleteId = await alice.deleteMessages(bobId, [
      SeqRange.single(ack.seq),
    ]);
    expect(deleteId, greaterThan(before));

    expect(await alice.getMessages(bobId, since: ack.seq), isEmpty);
    expect(
      (await bob.getMessages(aliceId, since: ack.seq)).map((m) => m.seq),
      contains(ack.seq),
    );

    final log = await alice.getDeleteLog(bobId, since: before + 1);
    expect(log.lastDeleteId, deleteId);
    expect(log.ranges.any((r) => r.contains(ack.seq)), isTrue);
    expect(
      await alice.getDeleteLog(bobId, since: deleteId + 1),
      DeleteLog.empty,
    );
  });

  test('a hard delete reaches other sessions as pres del', () async {
    final group = await alice.subscribe('new');
    final (other, _) = await loginAs('alice');
    await other.subscribe(group);

    final ack = await alice.publish(group, PlainText(unique('hard')));
    final deleted = other.presence.firstWhere(
      (p) => p.topic == group && p.event == PresenceEvent.deleted,
    );
    final deleteId = await alice.deleteMessages(group, [
      SeqRange.single(ack.seq),
    ], hard: true);

    final pres = await deleted.timeout(const Duration(seconds: 5));
    expect(pres.lastDeleteId, deleteId);
    expect(pres.deletedRanges, [SeqRange.single(ack.seq)]);
    expect(await other.getMessages(group, since: ack.seq), isEmpty);
  });

  test('ims on me returns the chats with new messages', () async {
    await alice.subscribe('me');
    final chats = await alice.getSubscriptions('me');
    final since = chats
        .expand((c) => [?c.updated, ?c.lastMessageAt])
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final ack = await bob.publish(aliceId, PlainText(unique('ims')));
    final changed = await alice.getSubscriptions('me', ifModifiedSince: since);
    final chat = changed.singleWhere((c) => c.topic == bobId);
    expect(chat.lastSeq, ack.seq);
  });

  test('ims on a description keeps the counters only', () async {
    final full = (await alice.getDescription(bobId))!;
    expect(full.public, isNotNull);

    final since = [
      ?full.updated,
      ?full.created,
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    final ack = await bob.publish(aliceId, PlainText(unique('desc')));
    final changed = (await alice.getDescription(
      bobId,
      ifModifiedSince: since,
    ))!;
    expect(changed.public, isNull);
    expect(changed.lastSeq, greaterThanOrEqualTo(ack.seq));
  });

  test('restore connects and logs in with the token', () async {
    final (_, login) = await loginAs('alice');
    final restored = TinodeClient.restore(config, token: login.token);
    addTearDown(restored.close);
    final connected = await restored.statusChanges
        .firstWhere((s) => s is Connected)
        .timeout(const Duration(seconds: 5));
    expect((connected as Connected).login?.userId, login.userId);
    expect(restored.serverInfo.version, isNotEmpty);
    expect(await restored.getDescription('me'), isA<TopicDescription>());
  });
}
