# tinode_dart_client

A pure-Dart client for the [Tinode](https://github.com/tinode/chat) chat server.
It speaks Tinode's JSON-over-WebSocket protocol and runs on the Dart VM, Flutter
and the web.

## Features

- Connect, then log in with a password or a token.
- Read the chat list, topic descriptions and message history.
- Send plain-text or [Drafty](https://github.com/tinode/chat/blob/master/docs/drafty.md) messages.
- Receive messages, presence and typing/read notifications as typed streams.
- Signalling for 1:1 voice and video calls, to pair with any WebRTC stack.
- Delete messages, and the building blocks of a local cache: serialisable
  models, "if modified since" queries, the delete log, and a client that
  starts offline from a remembered token.
- Typed end to end:
  - every server packet is a sealed class, so a `switch` over it is exhaustive;
  - the protocol fields of each packet are checked on arrival;
  - app-defined fields (`public`, `private`, message content) are read leniently,
    with the original JSON kept.

## Getting started

You need a Tinode server and its API key. To try it locally, the official image
`tinode/tinode-postgres` ships sample users (`alice` / `alice123`, `bob` / `bob123`…)
and the demo key `AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K`.

```sh
dart pub add tinode_dart_client
```

## Usage

```dart
import 'package:tinode_dart_client/tinode_dart_client.dart';

final client = await TinodeClient.connect(
  TinodeConfig(
    server: Uri.parse('wss://chat.example.com'),
    apiKey: '<your API key>',
    userAgent: 'MyApp/1.0',
  ),
);

final session = await client.loginBasic('alice', 'alice123');
// Keep session.token and use loginToken() on later connections.

client.messages.listen((m) => print('${m.topic} #${m.seq}: ${m.content.text}'));

await client.subscribe('me');
final chats = await client.getSubscriptions('me');

final topic = await client.subscribe(chats.first.topic!);
final history = await client.getMessages(topic, limit: 20);
await client.publish(topic, const PlainText('Hello!'));
client.markRead(topic, history.last.seq);

await client.close();
```

Request methods return the server's reply. A rejected request throws a
`ServerException` with the server's code. `events` (and the narrower `messages`,
`presence` and `info`) carry only what the server sends on its own.

## Staying connected

When the socket drops, the client reconnects on its own: it waits with
jittered exponential backoff, logs in again with the latest token and
re-attaches every topic you subscribed to. Your stream listeners stay in place.
While it is down, requests fail fast with `ConnectionClosedException`.

```dart
client.statusChanges.listen((status) {
  switch (status) {
    case Connected(:final login):
      // Each login renews the token: keep the new one.
      if (login != null) saveToken(login.token);
      // Messages sent meanwhile are not replayed: fetch them by seq.
      catchUp();
    case Reconnecting(:final retryIn):
      showBanner('Reconnecting in ${retryIn.inSeconds}s');
    case Disconnected(:final cause):
      // Final: closed by you, or the server refused the session.
      if (cause case ServerException(code: 401)) askForLogin();
    case Suspended():
      break;
  }
});
```

Mobile networks can kill a socket without closing it, so after 25 s of silence
the client sends Tinode's probe and drops a socket that doesn't answer.

The package doesn't depend on Flutter. Feed it the app's lifecycle yourself,
for example by closing the socket a little after the app goes to the
background (push notifications cover it meanwhile):

```dart
Timer? pause;
final listener = AppLifecycleListener(
  onHide: () => pause = Timer(const Duration(seconds: 15), client.suspend),
  onShow: () {
    pause?.cancel();
    client.resume(); // reconnects now, or probes a link that looks alive
  },
);
```

Network changes from the OS (e.g. `connectivity_plus`) are a useful hint,
not proof: let the socket decide. While connected, a change makes a dead
socket likely, so probe it with a short deadline; while reconnecting, it means
there is no point waiting out the backoff.

```dart
Connectivity().onConnectivityChanged.listen((networks) {
  switch (client.status) {
    case Connected():
      client.resume(probeTimeout: const Duration(seconds: 4));
    case Reconnecting() when !networks.contains(ConnectivityResult.none):
      client.resume();
    case _:
      // Suspended on purpose, or closed for good: not ours to wake.
  }
});
```

See [`example/main.dart`](example/main.dart) for a runnable program.

## Calls

The client carries the signalling of Tinode's 1:1 calls; the media is up to
your WebRTC stack (e.g. `flutter_webrtc`). The server only takes calls when it
has ICE servers, which it hands out in `serverInfo`:

```dart
if (client.serverInfo.callsEnabled) {
  // Pass client.serverInfo.iceServers to your RTCPeerConnection.
  final call = await client.startCall(peerTopic, audioOnly: true);

  client.info
      .where((i) => i.seq == call.seq && i.callEvent == CallEvent.accept)
      .listen((_) async {
        final offer = await createOffer(); // your WebRTC code
        client.sendCallEvent(
          peerTopic,
          call.seq,
          CallEvent.offer,
          payload: offer.toJson(),
        );
      });
}
```

The callee sees the call as a message whose `head.callState` is
`CallState.started`, attaches the topic, and answers with `ringing`, `accept`
and the WebRTC `answer`. The server updates the call message as the call goes
on (`accepted`, then `finished`, `missed`, `declined`…). See the
[glossary](docs/glossary.md#calls) for the whole flow.

## Caching and offline

The client keeps no state of its own, but gives a cache what it needs:

- every model has a `toJson()` that its `fromJson` reads back, so a store can
  keep the wire form;
- `getMessages(since:)` fetches what came after the newest cached seq;
- `getSubscriptions('me', ifModifiedSince:)` and
  `getDescription(ifModifiedSince:)` return only what changed. A `public` or
  `private` left out of the reply is unchanged, not cleared;
- `getDeleteLog(since:)` lists the messages deleted after a known delete ID
  (`Subscription.lastDeleteId`), and `pres del` reports new deletions live;
- `publish(head:)` can tag a message with your own ID. The server has no
  idempotency key, so after a drop look for that ID before sending again.

```dart
// Open offline: no waiting for the server, which may be unreachable.
final client = TinodeClient.restore(config, token: savedToken);
client.statusChanges.listen((status) {
  if (status case Connected(:final login?)) saveToken(login.token);
});
```

`restore` connects in the background like a reconnect. Requests fail with
`ConnectionClosedException` until it is `Connected`, and a refused token ends
in `Disconnected`.

## Current limits

Not built yet:

- account creation and profile updates (`acc`, `set`);
- deleting topics, subscriptions or users (`del` beyond messages);
- searching users and topics (`fnd`);
- file uploads.

## License

MIT. Tinode's server is GPL-3.0. This package only talks to the server over its
network protocol and contains no server code.
