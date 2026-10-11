@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against a Tinode server, which needs ICE servers configured
// (ICE_SERVERS_FILE) to take calls. The server passes call
// payloads on unread, so fake SDP is enough.
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

Future<T> waitFor<T>(Stream<T> stream, bool Function(T) test) =>
    stream.firstWhere(test).timeout(const Duration(seconds: 5));

Future<InfoMessage> callInfo(TinodeClient client, int seq, CallEvent event) =>
    waitFor(client.info, (i) => i.seq == seq && i.callEvent == event);

/// The server's update to call [seq] that sets [state].
Future<DataMessage> callUpdate(TinodeClient client, int seq, CallState state) =>
    waitFor(
      client.messages,
      (m) => m.head?.replacesSeq == seq && m.head?.callState == state,
    );

void main() {
  late TinodeClient alice;
  late TinodeClient bob;
  late String aliceId;
  late String bobId;

  setUp(() async {
    (alice, aliceId) = await loginAs('alice');
    (bob, bobId) = await loginAs('bob');
  });

  /// Alice calls bob, who is attached to the chat unless [bobAttached] is
  /// false. A call left running would make the next test's call busy, so
  /// it is hung up afterwards in case the test did not end it.
  Future<int> call({bool audioOnly = false, bool bobAttached = true}) async {
    await alice.subscribe(bobId);
    if (bobAttached) await bob.subscribe(aliceId);
    final seq = (await alice.startCall(bobId, audioOnly: audioOnly)).seq;
    addTearDown(() {
      try {
        alice.sendCallEvent(bobId, seq, CallEvent.hangUp);
      } on TinodeException catch (_) {}
    });
    return seq;
  }

  test('the server hands out its ICE servers', () {
    expect(alice.serverInfo.callsEnabled, isTrue);
    expect(alice.serverInfo.iceServers, hasLength(5));
    expect(alice.serverInfo.callTimeout, isNotNull);
  });

  test('a call from invite to hang-up', () async {
    await bob.subscribe('me');
    final pres = waitFor(
      bob.presence,
      (p) => p.event == PresenceEvent.message && p.source == aliceId,
    );
    final seq = await call(audioOnly: true, bobAttached: false);

    // Bob is not in the chat: the call reaches him as a new message on me.
    expect((await pres).seq, seq);
    await bob.subscribe(aliceId);
    final started = (await bob.getMessages(aliceId, since: seq)).first;
    expect(started.seq, seq);
    expect(started.from, aliceId);
    expect(started.head?.callState, CallState.started);
    expect(started.head?.audioOnly, isTrue);

    final ringing = callInfo(alice, seq, CallEvent.ringing);
    bob.sendCallEvent(aliceId, seq, CallEvent.ringing);
    expect((await ringing).from, bobId);

    final accept = callInfo(alice, seq, CallEvent.accept);
    final accepted = callUpdate(alice, seq, CallState.accepted);
    bob.sendCallEvent(aliceId, seq, CallEvent.accept);
    await accept;
    // The server writes updates in the caller's name.
    expect((await accepted).from, aliceId);

    const offer = CallDescription(type: 'offer', sdp: 'v=0\r\no=- 1 2 IN\r\n');
    final offered = callInfo(bob, seq, CallEvent.offer);
    alice.sendCallEvent(bobId, seq, CallEvent.offer, payload: offer.toJson());
    expect((await offered).description, offer);

    const answer = CallDescription(type: 'answer', sdp: 'v=0\r\n');
    final answered = callInfo(alice, seq, CallEvent.answer);
    bob.sendCallEvent(aliceId, seq, CallEvent.answer, payload: answer.toJson());
    expect((await answered).description, answer);

    const candidate = IceCandidate(
      candidate: 'candidate:1 1 udp 2122260223 10.0.0.1 9 typ host',
      sdpMid: '0',
      sdpMLineIndex: 0,
    );
    final candidates = callInfo(bob, seq, CallEvent.iceCandidate);
    alice.sendCallEvent(
      bobId,
      seq,
      CallEvent.iceCandidate,
      payload: candidate.toJson(),
    );
    expect((await candidates).candidate, candidate);

    final aliceHungUp = callInfo(alice, seq, CallEvent.hangUp);
    final bobHungUp = callInfo(bob, seq, CallEvent.hangUp);
    final finished = callUpdate(alice, seq, CallState.finished);
    bob.sendCallEvent(aliceId, seq, CallEvent.hangUp);
    await (aliceHungUp, bobHungUp).wait;
    expect((await finished).head?.callDuration, isNotNull);
  });

  test('the caller hanging up first leaves a missed call', () async {
    final seq = await call();
    final missed = callUpdate(bob, seq, CallState.missed);
    alice.sendCallEvent(bobId, seq, CallEvent.hangUp);
    await missed;
  });

  test('the callee hanging up first declines the call', () async {
    final seq = await call();
    final declined = callUpdate(alice, seq, CallState.declined);
    bob.sendCallEvent(aliceId, seq, CallEvent.hangUp);
    await declined;
  });

  test('a chat holds one call at a time', () async {
    final seq = await call();
    await expectLater(
      alice.startCall(bobId),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 486)),
    );
    final missed = callUpdate(alice, seq, CallState.missed);
    alice.sendCallEvent(bobId, seq, CallEvent.hangUp);
    await missed;
  });

  test("bob's other devices learn that he accepted", () async {
    final (bobPhone, _) = await loginAs('bob');
    await bobPhone.subscribe('me');
    final seq = await call();

    final elsewhere = waitFor(
      bobPhone.info,
      (i) => i.topic == 'me' && i.callEvent == CallEvent.accept,
    );
    bob.sendCallEvent(aliceId, seq, CallEvent.accept);
    final info = await elsewhere;
    expect(info.seq, seq);
    expect(info.source, aliceId);

    final hungUp = waitFor(
      bobPhone.info,
      (i) => i.topic == 'me' && i.callEvent == CallEvent.hangUp,
    );
    bob.sendCallEvent(aliceId, seq, CallEvent.hangUp);
    expect((await hungUp).source, aliceId);
  });
}
