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

See [`example/main.dart`](example/main.dart) for a runnable program.

## Current limits

This release covers the online happy path. The following are not built yet:

- account creation and profile updates (`acc`, `set`);
- deleting messages or topics (`del`);
- searching users and topics (`fnd`);
- file uploads;
- reconnection;
- local cache and offline sync.

## License

MIT. Tinode's server is GPL-3.0. This package only talks to the server over its
network protocol and contains no server code.
