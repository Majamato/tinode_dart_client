# tinode_dart_client

A pure-Dart client for the [Tinode](https://github.com/tinode/chat) chat server.
It speaks Tinode's JSON-over-WebSocket protocol and runs on the Dart VM, Flutter
and the web.

## Features

- Connect, then log in with a password or a token.
- Read the chat list, topic descriptions and message history.
- Send plain-text or [Drafty](https://github.com/tinode/chat/blob/master/docs/drafty.md) messages.
- Receive messages, presence and typing/read notifications as typed streams.
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

## Current limits

This release covers the online path, including reconnection. Not built yet:

- account creation and profile updates (`acc`, `set`);
- deleting messages or topics (`del`);
- searching users and topics (`fnd`);
- file uploads;
- local cache and offline sync.

## License

MIT. Tinode's server is GPL-3.0. This package only talks to the server over its
network protocol and contains no server code.
