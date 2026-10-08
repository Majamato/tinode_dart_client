## 0.5.0

Finding people and starting chats.

- `TinodeClient.find` searches users and groups by tag on `fnd` and returns
  `FoundTopic`s (also `MetaMessage.found`). Searches take turns, since the
  server keeps one query at a time.
- `createGroup` creates a group, or a channel, with its first profile and tags,
  and returns the real `grp…`/`chn…` name. It is attached again after a
  reconnect like any other topic.
- `setSubscription` adds a member or changes access, `setDescription` changes
  `public`, `private` and `defacs`, and `setTags` replaces tags. On the wire
  they are `set` (`SetMeta`).
- `subscribe` documents that a user ID opens, or creates, the 1:1 chat.

## 0.4.0

Building blocks for a local cache and offline sync. The client stays
stateless; the cache itself lives in the app (see tinode_flutter_chat).

- Deleting messages: `TinodeClient.deleteMessages` (for this user, or for
  everyone with `hard`) returns the delete ID. `getDeleteLog` reads deletions
  missed while away (`DeleteLog`, `SeqRange`, `MetaMessage.deleteLog`).
  `PresMessage.lastDeleteId` and `deletedRanges` carry the deletions of a
  `pres del`.
- "If modified since": `getDescription(ifModifiedSince:)` and
  `getSubscriptions(ifModifiedSince:, limit:)`. Unchanged chats are left out,
  removed ones carry `Subscription.deleted`, and "not modified" gives `[]`.
- `publish(head:)` adds headers, e.g. an app's own `x-…` key.
- `TinodeClient.restore` starts a client for a remembered token without
  waiting for the server, so an app can open offline; `ServerInfo.unknown`
  stands in until the first `hi`.
- `toJson()` on `DataMessage`, `TopicDescription`, `Subscription`, `Profile`,
  `ProfilePhoto`, `PrivateSettings`, `MessageHead`, `Access`, `DefaultAccess`
  and `LastSeen`, read back by their `fromJson` (`DataMessage.fromJson` is
  new).
- Fix: a live message that arrives during `getMessages` and lies outside the
  requested seqs now reaches `messages` instead of the history page.
- `userId` follows the client's own logins after a reconnect or restore.

## 0.3.0

- Call signalling for 1:1 voice and video calls; bring your own WebRTC stack.
  `TinodeClient.startCall` publishes the call message and `sendCallEvent` sends
  its steps (`CallEvent`). Incoming steps arrive on `info` with
  `InfoMessage.callEvent`, `payload` (see `description`, `candidate`) and
  `source`.
- `ServerInfo.iceServers` (`IceServer`), `callTimeout` and `callsEnabled`.
- `MessageHead.callState` (`CallState`), `callDuration`, `audioOnly` and
  `replacesSeq`.
- `Drafty.videoCall` and `Entity.videoCallType`.
- **Breaking:** `InfoMessage.from` is nullable: the server sends call
  hang-ups without it. Such infos used to fail as malformed packets.

## 0.2.0

- Reconnection: after a drop the client reconnects with jittered backoff, logs
  in again with the latest token and re-attaches its topics. See
  `ConnectionStatus`, `TinodeClient.status`/`statusChanges`, `ReconnectPolicy`.
- `suspend()` and `resume()` to close the socket on purpose (e.g. in the
  background) and come back at once.
- `resume(probeTimeout:)` probes a live socket with a shorter deadline, for
  network changes reported by the OS.
- Dead-socket detection with Tinode's network probe (`TinodeConfig.probeAfter`,
  `probeTimeout`).
- `subscribe` retries a topic the server reports as locked (503).
- A network error on the socket now ends the connection cleanly instead of
  surfacing as an uncaught error.
- **Breaking:** `TinodeClient.withSocket` is gone; pass a `connector` to
  `connect` instead. An unreachable server now throws
  `ServerUnreachableException` (a `TinodeException`) instead of the platform's
  exception.
- **Breaking:** `leave` while disconnected succeeds without contacting the
  server, unless `unsubscribe` is set.

## 0.1.0

- `TinodeClient`: connect with `hi`, log in with `basic` or `token`, subscribe,
  read descriptions, chat lists and message history, publish, send notes, leave.
- Typed server packets (`ctrl`, `data`, `meta`, `pres`, `info`) and models
  (`Subscription`, `TopicDescription`, `Profile`, `PrivateSettings`, `Drafty`,
  `AccessMode`).
- Runs on the Dart VM, Flutter and the web.
