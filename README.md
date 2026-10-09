# tinode_dart_client

A pure-Dart client for the [Tinode](https://github.com/tinode/chat) chat server.
It speaks Tinode's JSON-over-WebSocket protocol and runs on the Dart VM, Flutter
and the web.

## Features

- Connect, then log in with a password or a token.
- Read the chat list, topic descriptions and message history.
- Send plain-text or [Drafty](https://github.com/tinode/chat/blob/master/docs/drafty.md) messages.
- Receive messages, presence and typing/read notifications as typed streams.
- Find users and groups by tag, open 1:1 chats, create groups and add
  members.
- Read a chat's members, with their profiles and read/received counters, for
  sender names and per-message receipts.
- Signalling for 1:1 voice and video calls, to pair with any WebRTC stack.
- Images and files: upload and download over HTTP, and Drafty image and file
  entities to send and read them.
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

## Finding people and starting chats

`find` searches users and groups by their tags. A space means AND, a comma OR;
logins carry the `basic:` prefix, while emails and phone numbers match as
typed. A user comes back under their user ID, which is also the name of the
1:1 chat with them:

```dart
final found = await client.find('basic:bob,bob@example.com');
final bob = found.first; // a FoundTopic: topic, public profile, matched tags
await client.subscribe(bob.topic); // opens the 1:1 chat, creating it the first time
```

A group is created with its first profile and tags, and members are added by
user ID. They can read it at once; their `me` gets a `pres acs` naming it.

```dart
final group = await client.createGroup(
  public: const Profile(name: 'Hikers'),
  tags: ['hiking'],
);
await client.setSubscription(group, userId: bob.topic);
```

The creator of a chat gets no `pres` for it: refresh the chat list
(`getSubscriptions('me')`) after creating one.

## Group chats

A chat's members come from `getSubscriptions` on its topic: each has a
`userId`, a `public` profile for sender names and avatars, and the `read` and
`received` counters receipts are made of. Their changes arrive on `info` while
the chat is attached:

```dart
final members = {
  for (final m in await client.getSubscriptions(group)) m.userId!: m,
};
client.info.where((i) => i.topic == group).listen((i) {
  switch (i.event) {
    case InfoEvent.read || InfoEvent.received:
      // Raise members[i.from]'s counter to i.seq: a message is read by
      // everyone once every other member's read is at least its seq.
      break;
    case InfoEvent.typing:
      showTyping(members[i.from]?.public?.name);
    case _:
      break;
  }
});
```

Mark messages received as they arrive (`markReceived`), even for chats you
aren't attached to, after a `pres msg` on `me`; read markers count only from
an attached chat. A member who joins or leaves shows as `pres acs` on the
topic, with `source` naming them: fetch that one with
`getSubscriptions(group, userId: source)`, where `[]` means they left.
In a 1:1 chat the members carry counters but no profile: the peer's profile
is the chat's.

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

## Attachments

Files travel over HTTP, beside the socket: upload the file, put its `ref` into
a Drafty entity and publish the message before the upload's `expires`. Files
no message refers to are deleted.

```dart
final upload = await client.upload(
  () => file.openRead(), // called again if the server redirects the upload
  length: await file.length(),
  filename: 'photo.jpg',
  mimeType: 'image/jpeg',
  onProgress: (sent, total) => print('$sent / $total'),
);
await client.publish(
  topic,
  DraftyContent(
    Drafty.image(
      DraftyImage(
        ref: upload.ref,
        mimeType: 'image/jpeg',
        width: 1024,
        height: 768,
        size: await file.length(),
      ),
      caption: 'At the top',
    ),
  ),
);
```

`publish` tells the server which uploads the message uses
(`extra.attachments`); `setDescription` and `createGroup` do the same for a
profile photo given by `ref`. Use `Drafty.file` for any other file.

On the receiving side, `Drafty.images`, `Drafty.files` and `Drafty.caption`
read a message. A small file may come inline (`inlineData`, decoded by
`bytes`); otherwise download its `ref`:

```dart
for (final image in drafty.images) {
  final bytes = image.bytes ??
      await http.ByteStream((await client.download(image.ref!)).bytes).toBytes();
}
```

Both calls need a login but not a live socket, so they keep working while the
client reconnects. Credentials go only to the server's own origin, as headers:
a `ref` elsewhere, or a redirect to storage elsewhere, is fetched without them.
A refusal throws `ServerException` (413 means too large, see
`serverInfo.maxFileUploadSize`), a network failure
`ServerUnreachableException`, and completing an `abortTrigger` cancels a
transfer with `TransferAbortedException`. On the web, the server's
`cors_origins` must allow the app, and the browser buffers uploads, so
progress jumps.

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

## Roadmap

Built so far: the happy path, reconnection, calls, offline building blocks, finding people and
starting chats, group chat essentials, attachments. Next, in this order, each feature landing here first and then in
[`tinode_flutter_chat`](../tinode_flutter_chat):

1. ~~**Find people and start chats**~~: done in 0.5.0 (`find`, `createGroup`,
   `setSubscription`, `setDescription`, `setTags`).
2. ~~**Group chat essentials**~~: done in 0.6.0 (members with `getSubscriptions(userId:)`,
   receipts and typing from `info`).
3. ~~**Attachments**~~: done in 0.7.0 (`upload`, `download`, `resolveFile`,
   `Drafty.image`/`file`, `extra.attachments`).
4. **Account and profile**: account creation (`acc`), profile and password changes, deleting
   topics, subscriptions and users (`del` beyond messages).
5. **Push**: registering the device token for push notifications (`hi dev`).
6. Local search and cache upkeep happen in the Flutter package only.
7. UI/UX work happens in the Flutter package only.

## License

MIT. Tinode's server is GPL-3.0. This package only talks to the server over its
network protocol and contains no server code.
