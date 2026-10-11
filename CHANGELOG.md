## 0.9.0

Push notifications.

- `TinodeClient.setDeviceToken(token)` registers the device's push token for
  the logged-in user (`hi dev`), and `setDeviceToken(null)` removes it
  (`dev: ␡`). The client keeps the token: every session's `hi` carries it,
  after a reconnect or `restore` too, and one set before login is sent once a
  login succeeds.
- `TinodeConfig.platform` (`DevicePlatform`) tells the server the device's OS
  (`hi platf`).
- `TinodeConfig.copyWith`.
- `TinodePush.tryParse(data)` reads the data of a push from the server:
  `MessagePush` (with the text, a Drafty preview and call state),
  `SubscriptionPush` or `ReadPush`, and null for anything else. It needs no
  client, so it works in a background handler.

## 0.8.0

Account and profile.

- `TinodeClient.createAccount` signs up with a login and password (`acc`) and
  logs the session in as the new user; reconnects log in with its token. 409
  means the login is taken, 422 that the server's rules refuse it.
- `createAccount(email:)` gives the account an email to confirm. Servers that
  send mail usually require one (`ServerInfo.requiredCredentials`, from the
  `hi` reply's `reqCred`); the server mails a code, and `loginBasic` and
  `loginToken` send it back with `codes: {'email': code}`.
- **Breaking:** code 300 on a login or a sign-up (credentials to confirm)
  throws `CredentialsRequiredException` (`methods`, `userId`) instead of
  `ServerException`. A reconnect that gets it ends in `Disconnected`
  instead of retrying.
- `changePassword(password, login:)` changes the password, and the login.
- `requestPasswordReset(email)` and `resetPassword(email:, code:, password:)`:
  the server emails a code, sent back as a one-off `code` login
  (`tmpscheme`). Asking again while a code is valid is 409.
- `deleteTopic` deletes a chat (`del what=topic`): for everyone when the
  owner deletes a group, otherwise only for this user. The topic is no longer
  attached after a reconnect.
- `deleteSubscription(topic, userId:)` removes a member (`del what=sub`); one
  who isn't a member counts as removed.
- `deleteAccount` deletes the user (`del what=user`) and closes the client.
- A topic the server evicts this user from (`ctrl` 205) is no longer attached
  after a reconnect.
- `Profile.copyWith` edits a profile read from the server without losing its
  other theCard fields (`raw` wins in `toJson`).

## 0.7.0

Attachments.

- `TinodeClient.upload` sends a file over HTTP (`/v0/file/u/`) and returns an
  `UploadResult` (`ref`, `expires`); `download` fetches one (`FileDownload`).
  Both log in with the latest token as headers, so they work while
  reconnecting, and send credentials only to the server's own origin,
  following redirects by hand. Upload progress, aborting
  (`TransferAbortedException`), and network failures as
  `ServerUnreachableException`.
- `TinodeConfig.httpBase`, `uploadUri`, `resolveFile` and `tryResolveFile`
  (refs to URLs, `http` and `https` only) and `attachmentPath`; `TinodeClient.config`.
- `connect` and `restore` take an `httpClient`; the client closes only one it
  made. New dependency: `http`.
- `publish`, `setDescription` and `createGroup` list the uploads their content
  or profile photo use in the packet's `extra.attachments`, so the server keeps
  them.
- Drafty images and files: `DraftyImage`, `DraftyFile`, `Entity.asImage`,
  `Entity.asFile`, `Drafty.images`, `Drafty.files`, `Drafty.caption`, and the
  builders `Drafty.image` and `Drafty.file` in TinodeWeb's layout.

## 0.6.0

Group chat essentials.

- `getSubscriptions(topic, userId:)` reads one member (`get sub` with
  `user`); `[]` means they aren't one. Without it, a non-`me` topic gives all
  its members, with their profiles and `read`/`received` counters.
- Documented, and tested on a live server: other members' read and received
  markers arrive on `info`; `markReceived` counts from a chat that isn't
  attached, `markRead` doesn't; members joining or leaving show as `pres acs`
  with `source` naming them; a 1:1 chat's members carry no profile.

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
