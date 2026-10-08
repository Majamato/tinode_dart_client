@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against ../tinode-tests (sample users alice and bob). Each run creates
// a group under a unique tag, so earlier runs' groups don't match.
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

String uniqueTag() => 'probe${DateTime.now().microsecondsSinceEpoch}';

void main() {
  late TinodeClient alice;
  late TinodeClient bob;
  late String bobId;

  setUp(() async {
    final (a, _) = await loginAs('alice');
    final (b, bobLogin) = await loginAs('bob');
    alice = a;
    bob = b;
    bobId = bobLogin.userId;
  });

  test('a login tag finds the user, whose ID opens the 1:1 chat', () async {
    final found = await alice.find('basic:bob');
    final user = found.singleWhere((f) => f.topic == bobId);
    expect(user.kind, TopicKind.direct);
    expect(user.public?.name, isNotEmpty);
    expect(user.matchedTags, ['basic:bob']);

    expect(await alice.subscribe(user.topic), bobId);
  });

  test('a query that matches nothing finds nothing', () async {
    expect(await alice.find(uniqueTag()), isEmpty);
  });

  test('a comma finds either; searches in a row each get theirs', () async {
    final results = await Future.wait([
      alice.find('basic:bob,basic:carol'),
      alice.find('basic:bob'),
    ]);
    expect(results.first, hasLength(2));
    expect(results.last.single.topic, bobId);
  });

  test('a new group is findable, and an added member gets it', () async {
    final tag = uniqueTag();
    await bob.subscribe('me');
    final invited = bob.presence.firstWhere(
      (p) => p.topic == 'me' && p.event == PresenceEvent.access,
    );
    final since = DateTime.now().subtract(const Duration(seconds: 5));

    final group = await alice.createGroup(
      public: const Profile(name: 'Probe group'),
      tags: [tag],
    );
    expect(TopicKind.of(group), TopicKind.group);
    final found = (await alice.find(tag)).single;
    expect(found.topic, group);
    expect(found.public?.name, 'Probe group');
    expect(found.memberCount, 1);

    final access = await alice.setSubscription(group, userId: bobId);
    expect(access?.mode.has(Permission.read), isTrue);
    expect((await invited).source, group);

    final chats = await bob.getSubscriptions('me', ifModifiedSince: since);
    final chat = chats.singleWhere((s) => s.topic == group);
    expect(chat.public?.name, 'Probe group');

    final ack = await alice.publish(group, const PlainText('welcome'));
    await bob.subscribe(group);
    final history = await bob.getMessages(group, since: ack.seq);
    expect(history.single.content.text, 'welcome');
  });

  test('only a member with S may add others', () async {
    final group = await alice.createGroup(
      public: const Profile(name: 'Closed group'),
    );
    final given = await alice.setSubscription(
      group,
      userId: bobId,
      mode: AccessMode.parse('JRWP'),
    );
    expect(given?.given.has(Permission.share), isFalse);
    await bob.subscribe(group);
    final (carol, carolLogin) = await loginAs('carol');
    await carol.close();
    await expectLater(
      bob.setSubscription(group, userId: carolLogin.userId),
      throwsA(isA<ServerException>()),
    );
  });
}
