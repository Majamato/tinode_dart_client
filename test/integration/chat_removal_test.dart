@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import 'account_test.dart' show signUp;

/// The next `pres` on [client]'s `me` about [source].
Future<PresMessage> nextOnMe(
  TinodeClient client,
  String source,
  PresenceEvent event,
) => client.presence
    .firstWhere(
      (p) => p.topic == 'me' && p.source == source && p.event == event,
    )
    .timeout(const Duration(seconds: 5));

void main() {
  late TinodeClient owner;
  late TinodeClient member;
  late String memberId;
  late String group;

  setUp(() async {
    final (o, _) = await signUp('po');
    final (m, memberLogin) = await signUp('pm');
    owner = o;
    member = m;
    memberId = memberLogin.userId;
    await member.subscribe('me');
    group = await owner.createGroup(public: const Profile(name: 'Removal'));
    await owner.setSubscription(group, userId: memberId);
  });

  test('a removed member is evicted and told the chat is gone', () async {
    await member.subscribe(group);
    final evicted = member.events
        .firstWhere((m) => m is CtrlMessage && m.code == 205)
        .timeout(const Duration(seconds: 5));
    final gone = nextOnMe(member, group, PresenceEvent.gone);

    await owner.deleteSubscription(group, userId: memberId);
    expect((await evicted).topic, group);
    await gone;
    expect(await owner.getSubscriptions(group, userId: memberId), isEmpty);

    // Removing them again changes nothing, without an error.
    await owner.deleteSubscription(group, userId: memberId);
  });

  test('removing a member needs the chat attached', () async {
    await owner.leave(group);
    await expectLater(
      owner.deleteSubscription(group, userId: memberId),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 409)),
    );
  });

  test('a member deleting the group only leaves it', () async {
    final left = owner.presence
        .firstWhere((p) => p.topic == group && p.source == memberId)
        .timeout(const Duration(seconds: 5));
    await member.deleteTopic(group);
    await left;
    expect(await owner.getSubscriptions(group, userId: memberId), isEmpty);
    expect(await owner.getDescription(group), isNotNull);
  });

  test('the owner deleting the group deletes it for everyone', () async {
    final gone = nextOnMe(member, group, PresenceEvent.gone);
    await owner.deleteTopic(group);
    await gone;
    final chats = await member.getSubscriptions('me');
    expect(chats.map((c) => c.topic), isNot(contains(group)));
  });

  test('deleting a 1:1 chat leaves the peer their side', () async {
    final ownerId = owner.userId!;
    await owner.subscribe(memberId);
    await owner.publish(memberId, const PlainText('hi'));
    await owner.deleteTopic(memberId);

    expect(
      (await owner.getSubscriptions('me')).map((c) => c.topic),
      isNot(contains(memberId)),
    );
    expect(
      (await member.getSubscriptions('me')).map((c) => c.topic),
      contains(ownerId),
    );
  });
}
