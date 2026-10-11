@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against a Tinode server with the sample data (users alice, bob, carol
// and dave).
// Each test creates its own group.
final config = TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
  userAgent: 'tinode_dart_client-test/0.1',
);

Future<(TinodeClient, String)> loginAs(String user) async {
  final client = await TinodeClient.connect(config);
  addTearDown(client.close);
  return (client, (await client.loginBasic(user, '${user}123')).userId);
}

Future<InfoMessage> nextInfo(
  TinodeClient client,
  String topic,
  InfoEvent event,
) => client.info.firstWhere((i) => i.topic == topic && i.event == event);

Future<PresMessage> nextPres(
  TinodeClient client,
  String topic,
  PresenceEvent event,
) => client.presence.firstWhere((p) => p.topic == topic && p.event == event);

void main() {
  late TinodeClient alice;
  late TinodeClient bob;
  late TinodeClient carol;
  late String aliceId;
  late String bobId;
  late String carolId;
  late String group;

  setUp(() async {
    (alice, aliceId) = await loginAs('alice');
    (bob, bobId) = await loginAs('bob');
    (carol, carolId) = await loginAs('carol');
    group = await alice.createGroup(public: const Profile(name: 'Members'));
    await alice.setSubscription(group, userId: bobId);
    await alice.setSubscription(group, userId: carolId);
    await bob.subscribe(group);
    await carol.subscribe(group);
  });

  test('members come with their profile, access and counters', () async {
    final members = await bob.getSubscriptions(group);
    expect(
      members.map((m) => m.userId),
      unorderedEquals([aliceId, bobId, carolId]),
    );
    for (final member in members) {
      expect(member.topic, isNull);
      expect(member.public?.name, isNotEmpty);
      expect(member.access?.mode.has(Permission.read), isTrue);
    }

    final one = await carol.getSubscriptions(group, userId: bobId);
    expect(one.single.userId, bobId);
    final (_, daveId) = await loginAs('dave');
    expect(await carol.getSubscriptions(group, userId: daveId), isEmpty);
  });

  test("a member's received and read reach the attached members", () async {
    final ack = await bob.publish(group, const PlainText('hi'));
    final received = nextInfo(alice, group, InfoEvent.received);
    carol.markReceived(group, ack.seq);
    expect((await received).from, carolId);
    expect((await received).seq, ack.seq);

    final read = nextInfo(bob, group, InfoEvent.read);
    carol.markRead(group, ack.seq);
    expect((await read).from, carolId);
    expect((await read).seq, ack.seq);

    final members = await alice.getSubscriptions(group);
    final carolNow = members.singleWhere((m) => m.userId == carolId);
    expect(carolNow.read, ack.seq);
    // Publishing moves the sender's own counters to their message.
    final bobNow = members.singleWhere((m) => m.userId == bobId);
    expect((bobNow.read, bobNow.received), (ack.seq, ack.seq));
  });

  test('read leaves received behind', () async {
    final ack = await bob.publish(group, const PlainText('hi'));
    final read = nextInfo(alice, group, InfoEvent.read);
    carol.markRead(group, ack.seq);
    await read;
    final members = await alice.getSubscriptions(group);
    final carolNow = members.singleWhere((m) => m.userId == carolId);
    expect((carolNow.read, carolNow.received), (ack.seq, 0));
  });

  test('received counts from a session not attached; read does not', () async {
    await carol.leave(group);
    final ack = await bob.publish(group, const PlainText('hi'));
    final received = nextInfo(alice, group, InfoEvent.received);
    carol.markReceived(group, ack.seq);
    expect((await received).from, carolId);

    carol.markRead(group, ack.seq);
    // Carol's session handles her packets in order: once this is answered,
    // the note has been dealt with.
    await carol.getDescription('me');
    final members = await alice.getSubscriptions(group);
    final carolNow = members.singleWhere((m) => m.userId == carolId);
    expect((carolNow.read, carolNow.received), (0, ack.seq));
  });

  test('joining and leaving show as pres acs naming the member', () async {
    final (dave, daveId) = await loginAs('dave');
    final joined = nextPres(bob, group, PresenceEvent.access);
    await alice.setSubscription(group, userId: daveId);
    expect((await joined).source, daveId);
    final added = await bob.getSubscriptions(group, userId: daveId);
    expect(added.single.public?.name, isNotEmpty);

    await dave.subscribe(group);
    final left = nextPres(bob, group, PresenceEvent.access);
    await dave.leave(group, unsubscribe: true);
    expect((await left).source, daveId);
    expect(await bob.getSubscriptions(group, userId: daveId), isEmpty);
  });

  test('a 1:1 chat lists both users, with counters but no profile', () async {
    await alice.subscribe(bobId);
    final members = await alice.getSubscriptions(bobId);
    expect(members.map((m) => m.userId), unorderedEquals([aliceId, bobId]));
    expect(members.every((m) => m.public == null), isTrue);
  });
}
