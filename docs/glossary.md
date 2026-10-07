# Tinode glossary

The words Tinode uses, explained for people who don't know the server.
`code` marks a name that appears literally on the wire.
**In this package** shows where a term surfaces in `tinode_dart_client`.

Packet classes keep the wire names (`PresMessage` for `pres`), so they map one-to-one to the
protocol docs. Fields and enum values use plain words instead of the wire abbreviations
(`lastMessageAt` for `touched`, `PresenceEvent.online` for `on`); each entry below names both.

---

## Core concepts

**Session**
One network connection to the server: here, one WebSocket. A user can have several sessions open
at once (phone, laptop, web). There is no logout; closing the connection ends the session. The
server forgets a session's attached topics when it ends; the next one starts from `hi`.
*In this package:* one socket inside a `TinodeClient`. After a drop the client opens a new session
and restores the old one's login and attached topics, see [Reconnect](#reconnect).

**User**
An account. Each user has a **user ID** such as `usrMMHQIDZI0e8`. User IDs are URL-safe base64
without padding, after the `usr` prefix.

**Topic**
A named channel that messages flow through. Almost everything is a topic: a 1:1 chat, a group,
your own account (`me`), even search (`fnd`). See [Topic kinds](#topic-kinds).

**Subscription**
The lasting relationship between a user and a topic. It holds that user's permissions, read and
received counters, and private notes about the topic. It survives disconnects and is shared by all
the user's sessions.
*In this package:* `Subscription`.

**Attach / detach**
A session **attaches** to a topic with `sub` to receive its live traffic, and **detaches** with
`leave`. Detaching keeps the subscription. `leave` with `unsub: true` removes the subscription
itself, on every device.
*Avoid:* using "subscribe" for the live attachment alone; the subscription is the lasting part.

**Chat list**
The subscriptions of the `me` topic: every chat the user takes part in. You read it with
`get what=sub` on `me`.
*Avoid:* "contacts". Groups and channels are in the list too, and a P2P peer only shows up once a
chat exists.

**Member**
An entry in the subscriptions of any topic other than `me`: a user who belongs to that topic.

**Peer**
The other user in a P2P chat.

---

## Topic kinds

| Name | Meaning | `TopicKind` |
|------|---------|-------------|
| `me` | Your profile, your chat list and presence for all your chats. You can't post to it. | `account` |
| `fnd` | Finds users and topics by tags. You can't post to it. | `search` |
| `slf` | Notes to yourself; only you see them. | `notes` |
| `sys` | A write-only line to the administrators (e.g. abuse reports). | `system` |
| `usr…` | A 1:1 chat, called **P2P** (peer to peer) in Tinode's docs. **Each side names it after the other user**: Alice sees `usrBob`, Bob sees `usrAlice`. | `direct` |
| `grp…` | A chat with many members and per-member permissions. It has an owner. | `group` |
| `chn…` | A group whose messages read-only followers can also receive. Followers don't see who sent each message. | `channel` |
| `new…` | Subscribe to this to **create** a group. The reply gives the real `grp…` name. | `group` |
| `nch…` | Subscribe to this to **create** a channel. | `channel` |

*In this package:* `TopicKind.of(name)`. Names it doesn't recognise give `TopicKind.unknown`.

---

## Packets

**Packet**
One JSON object sent over the socket. It has a single top-level key that names its type, e.g.
`{"pub": {...}}`.

**Client packets** (sent by the app)

| Packet | Purpose |
|--------|---------|
| `hi` | Handshake. Must be the first packet; it reports the client version and user agent. |
| `acc` | Creates an account or changes credentials. |
| `login` | Authenticates the session. |
| `sub` | Attaches to a topic. Creates the topic or the subscription if needed. |
| `leave` | Detaches from a topic, and with `unsub` also unsubscribes. |
| `pub` | Publishes (sends) a message. |
| `get` | Reads something: description, members, messages, tags… |
| `set` | Changes something: description, permissions, tags… |
| `del` | Deletes messages, a subscription, a topic, a user or a credential. |
| `note` | A notification that gets no reply: typing, received, read. |

**Server packets** (received by the app)

| Packet | Purpose |
|--------|---------|
| `ctrl` | Control reply to a request: a status `code`, a `text` and `params`. |
| `data` | A message. The only packet that is stored. |
| `meta` | Metadata about a topic: description, subscriptions, tags… |
| `pres` | Presence or change event (someone came online, a chat changed). Not stored. |
| `info` | Another user's `note`, forwarded by the server (typing, read, received). Not stored. |

*In this package:* `ServerMessage` and its subclasses `CtrlMessage`, `DataMessage`,
`MetaMessage`, `PresMessage` and `InfoMessage`. `meta.desc` and `meta.sub` are
`MetaMessage.description` and `MetaMessage.subscriptions`.

**Request id** (`id`)
A string the client chooses for each request. The server repeats it on the reply so the client
can match the two. `data` packets never carry it, and `note` gets no reply at all.

**Status code** (`code`)
Uses HTTP meanings: `2xx` success, `3xx` more input needed, `4xx` client error, `5xx` server error.
Common ones:

| Code | Meaning |
|------|---------|
| 200 | ok |
| 201 | created (e.g. reply to `hi`) |
| 202 | accepted (reply to `pub`) |
| 204 | no content |
| 208 | delivered (closes a `get data` reply) |
| 300 | more credentials needed |
| 400 | malformed request |
| 401 | authentication failed |
| 409 | already authenticated |

*In this package:* codes ≥ 300 become `ServerException`.

**Echo**
The copy of your own message that the server sends back to every session attached to the topic,
including your own. `noecho` on `pub` suppresses it for the sending session.

**`what`**
A selector field whose meaning depends on the packet:
- in `get`, what to fetch: `desc`, `sub`, `data`, `tags`, `del`, `cred`;
- in `pres`, what changed;
- in `note` and `info`, which notification it is.

---

## Messages

**Message**
A `data` packet: something a user published to a topic. Its fields are `topic`, `from` (the
sender's user ID), `seq`, `ts`, `head` and `content`.

**seq**
A message's sequence number. It is assigned per topic and counts up 1, 2, 3… It is the basis for
pagination, unread counts and caching.
*In this package:* `seq` on messages. On a description or subscription, `seq` is the topic's
latest message, so it becomes `lastSeq`.

**ts**
Timestamp in RFC 3339 UTC, with millisecond precision.
*In this package:* `time`, as a `DateTime`.

**Content**
The message body: either a plain string or a **Drafty** document.
*In this package:* `MessageContent`, with the variants `PlainText`, `DraftyContent` and
`UnknownContent`.

**Head**
The headers of a message:
- `mime` (`text/x-drafty` for Drafty);
- `reply`: the message this one answers, as `topic:seq`;
- `replace`: the message this one edits, as `:seq`;
- `forwarded`, `mentions`, `attachments`…

- `webrtc`, `webrtc-duration`, `aonly`: the **call** a message stands for, see [Calls](#calls).

*In this package:* `MessageHead`, with `replace` as `replaces` (and its seq as `replacesSeq`) and
`reply` as `replyTo`.

**Drafty**
Tinode's rich-text format. It has three parts:
- `txt`: the plain text;
- `fmt`: **spans** that style parts of the text;
- `ent`: **entities** that spans can point to.

Zero values are left out on the wire.
*In this package:* `Drafty`, with `text`, `spans` and `entities`.

**Span** (one item of `fmt`)
A range `{at, len}` of the text. Either `tp` gives it an inline style (`ST` strong, `EM` emphasis,
`CO` code, `DL` deleted, `BR` line break…), or `key` points to an entity.
*In this package:* `Span`, with `at`, `length`, `style` and `entityIndex`.

**Entity** (one item of `ent`)
An object a span refers to, of type `tp`: `LN` link, `MN` mention, `HT` hashtag, `IM` image,
`EX` attachment, `BN` button… Its `data` depends on the type.
*In this package:* `Entity`, with `type` and `data`. `VC` marks a call message
(`Entity.videoCallType`, `Drafty.videoCall`).

**History**
Earlier messages, fetched with `get what=data` and the bounds `since` (inclusive), `before`
(exclusive) and `limit` (32 by default). The server returns the newest ones that match.

---

## Counters and state

**read / recv**
The highest `seq` the user has **read** or **received** in a topic. The client advances them by
sending `note read` or `note recv`.
*In this package:* the fields `read` and `received`, advanced with `markRead` and
`markReceived`.

**Unread**
`seq - read`: the number of messages the user hasn't read yet.

**touched**
When the last message was posted in the topic. Useful for sorting the chat list.
*In this package:* `lastMessageAt`.

**clear / delete ID**
Every delete operation gets a delete ID, and `clear` is the latest one. `delseq` lists the ranges
of message `seq`s that were deleted. Clients use these to catch up on deletions they missed.
*In this package:* `clear` is `lastDeleteId`.

**ims** ("if modified since")
A timestamp sent with `get` so the server returns only what changed since then. Meant for
caching.

---

## Profile data

**Description** (`desc`)
A topic's metadata:
- dates: `created`, `updated`, `touched`;
- permissions: `defacs`, `acs`;
- counters: `seq`, `read`, `recv`, `clear`;
- data: `public`, `private`, `trusted`.

*In this package:* `TopicDescription`.

**public**
Data that everyone with access to the topic or user can see. The user writes their own; the owner
writes a topic's. By convention it is a theCard, except on `fnd`, where it holds the search query
string.
*In this package:* `Profile` (see theCard below).

**private**
Data only the user can see and write, about a topic or about their own account. All their devices
share it. The app decides what goes in it, but Tinode documents these keys:

| Wire key | Meaning | In this package |
|----------|---------|-----------------|
| `comment` | the user's note about the topic or peer | `comment` |
| `arch` | the user archived the chat | `archived` |
| `accepted` | the access ("given" mode) the user accepted | `accepted` (an `AccessMode`) |
| `tpins` | topics pinned to the top of the chat list, on `me` only | `pinnedTopics` |

*In this package:* `PrivateSettings`, with other keys kept in `raw`.

**trusted**
Badges that only administrators can set, such as `verified`, `staff` or `danger`.

**aux**
Extra topic data that admins write, such as `pins` (pinned messages).

**theCard**
Tinode's name for the conventional shape of `public`, a JSON take on the vCard 3.0 contact card.
Fields: `fn` (formatted name), `photo`, `note`, `n` (structured name), `org`, `comm` (phone,
email, web…) and `bday`.
*In this package:* `Profile`, with `fn` as `name`, plus `photo` and `note`. The other fields stay
in `raw`.
*Avoid:* "card" in code; this package says "profile".

**photo**
An avatar inside theCard. Either `data` (inline base64, which can be large) or `ref` (a URL to an
uploaded file), plus `type` (`jpg`, `png`…).
*In this package:* `ProfilePhoto`.

**Tags**
Lowercase search keywords attached to users and topics, optionally with a prefix such as
`email:` or `tel:`. `fnd` searches by them: a space means AND, a comma means OR.

**`␡`** (U+2421)
The value that clears a field. Sending `null` leaves the field unchanged.

**x-…**
The prefix for custom keys an app adds to `public` or `private`, e.g. `x-example-com-role`.

---

## Access control

**Access mode**
A set of permissions written as letters:

| Letter | Permission |
|:------:|------------|
| `J` | join |
| `R` | read messages |
| `W` | write messages |
| `P` | get presence |
| `A` | approve: admin (accept, kick, ban members) |
| `S` | share: invite others |
| `D` | delete messages for everyone |
| `O` | owner |
| `N` | none |

*In this package:* `AccessMode` and `Permission`.

**want / given / mode** (`acs`)
- `want`: what the user asked for;
- `given`: what the topic granted;
- `mode`: what is in effect, which is `want` ∩ `given`.

*In this package:* `Access`; the field holding it is `access`.

**defacs**
The default access for new subscribers, split into `auth` (logged-in users) and `anon` (anonymous
users).
*In this package:* `DefaultAccess`; the field holding it is `defaultAccess`.

**Owner**
The user holding `O` on a group or channel. There is one per topic, and P2P topics have none.

---

## Authentication

**API key**
Identifies the app to the server and is required on every connection. It goes in the
`apikey` query parameter. The official Docker images ship a demo key; real deployments generate
their own.

**Auth scheme**
How a login is checked:

| Scheme | Use |
|--------|-----|
| `basic` | user name + password, sent as base64 of `user:password` |
| `token` | a token from an earlier login; the usual way to log in again |
| `anonymous` | temporary users |
| `rest` | delegated to an external service |
| `reset` | starts password recovery |

**Token**
Returned by a successful login together with `expires`. Use it with the `token` scheme until it
expires. Every login, a token login included, renews the expiry, so always keep the newest one.
*In this package:* `LoginResult.token` and `LoginResult.expires`; after a reconnect, the new one
is in `Connected.login`.

**authlvl**
The authentication level the session reached: `auth`, `anon` or `root`.

**Credential** (`cred`)
A contact method (`email`, `tel`) that the server may require to be validated. Validation happens
by sending back a code (`resp`) in `login` or `acc`. Until then, login answers with code 300.

---

## Presence and notifications

**Presence**
Whether a user is online. A user counts as online while any of their sessions is attached to `me`.
Changes arrive as `pres` packets.

**`pres` `what` values**

| Wire | Meaning | In this package |
|------|---------|-----------------|
| `on` / `off` | came online / went offline | `online` / `offline` |
| `ua` | switched client | `userAgent` |
| `upd` | description changed | `updated` |
| `acs` | permissions changed | `access` |
| `msg` | new message in a chat you're not attached to | `message` |
| `read` / `recv` | another session or user read / received | `read` / `received` |
| `del` | messages deleted | `deleted` |
| `gone` | topic deleted or you were removed | `gone` |
| `term` | session terminated | `terminated` |
| `tags` / `aux` | tags or aux changed | `tags` / `aux` |

On `me`, the `src` field says which chat or user the event is about.
*In this package:* `PresMessage.event` (a `PresenceEvent`) and `PresMessage.source`.
Values a newer server adds become `PresenceEvent.unknown`.

**seen**
For a P2P peer: when they were last online (`when`) and with which client (`ua`).
*In this package:* `LastSeen`, with `when` and `userAgent`.

**ua** (user agent)
A string identifying the client app, e.g. `MyApp/1.0`. It is sent in `hi` and shown to peers.
*In this package:* `userAgent`.

**Note** / **info** `what` values

| Wire | Meaning | In this package |
|------|---------|-----------------|
| `kp` | key press: the user is typing | `typing`, sent with `sendTyping` |
| `recv` | the user received up to `seq` | `received`, sent with `markReceived` |
| `read` | the user read up to `seq` | `read`, sent with `markRead` |
| `call` | one step of a call, see [Calls](#calls) | `call`, sent with `sendCallEvent` |

*In this package:* `InfoMessage.event` (an `InfoEvent`). A `call` info also has `callEvent`,
`payload` and, on `me`, `source`; its `from` is missing when the server ends the call.

---

## Calls

**Call**
A voice or video call between the two users of a P2P topic, carried by WebRTC. Tinode only relays
the signalling; audio and video flow between the devices, or through a TURN server. The caller
publishes a **call message** whose head has `webrtc: started` (and `aonly: true` for voice only),
and that message's `seq` names the call from then on. A topic holds one call at a time: a second
one gets code 486. Group topics can't have calls (403), and a server without **ICE servers**
refuses them (501).
*In this package:* `TinodeClient.startCall`, which returns the call's `seq`.

**Call event** (`event` of a `call` note or info)
One step of a call, sent with `{note what="call" seq event payload}` and forwarded to the peer as
`{info what="call" …}`:

| Wire | Meaning | In this package |
|------|---------|-----------------|
| `ringing` | the callee's device shows the call | `ringing` |
| `accept` | the callee took the call | `accept` |
| `offer` | the caller's SDP, after `accept` | `offer`, payload a **call description** |
| `answer` | the callee's SDP | `answer`, payload a **call description** |
| `ice-candidate` | a network path to try | `iceCandidate`, payload an **ICE candidate** |
| `hang-up` | end the call, or decline it | `hangUp` |

The callee must be attached to the topic for everything but `ringing`, `accept` and `hang-up`. The
server drops call notes it doesn't expect, without an error. When a call ends the server sends
`hang-up` to everyone attached, without `from`. On `me`, the callee's other devices get `accept`
and `hang-up` with `src` naming the chat, so they can stop ringing.
*In this package:* `CallEvent`, `TinodeClient.sendCallEvent`, and `InfoMessage.callEvent`,
`payload` and `source`.
*Avoid:* "invite": Tinode's docs mention it, but the server never sends it.

**Call state** (head `webrtc`)
Where a call stands. The server records each change by publishing a new message that replaces the
call message (`replace: ":<seq>"`), in the caller's name.

| Wire | Meaning | In this package |
|------|---------|-----------------|
| `started` | ringing | `started` |
| `accepted` | the callee took it | `accepted` |
| `finished` | ended after being accepted; `webrtc-duration` has the length in ms | `finished` |
| `missed` | not taken in time, or the caller gave up | `missed` |
| `declined` | the callee refused | `declined` |
| `disconnected` | a party dropped before it was accepted | `disconnected` |
| `busy` | documented, but never written by the server | `busy` |

The updates leave out `aonly`: only the call message itself says whether it is voice only.
*In this package:* `CallState`, `MessageHead.callState`, `callDuration` and `audioOnly`.

**Call timeout** (`callTimeout` in the `hi` reply)
How many seconds a call may ring before the server ends it as missed.
*In this package:* `ServerInfo.callTimeout`.

**ICE server**
A STUN or TURN server that helps WebRTC through NAT and firewalls. The server hands its list out in
the `hi` reply (`iceServers`), in WebRTC's own shape except for `credential_type`.
*In this package:* `IceServer`, `ServerInfo.iceServers` and `callsEnabled`.

**Call description**
The payload of `offer` and `answer`: a WebRTC session description, `{type, sdp}`.
*In this package:* `CallDescription`.
*Avoid:* "session description", which clashes with **Session**.

**ICE candidate**
The payload of `ice-candidate`: `{candidate, sdpMid, sdpMLineIndex, usernameFragment}`.
*In this package:* `IceCandidate`.

---

## Connection

**Reconnect**
Not a protocol feature: the client does it. When the socket drops, it waits, opens a new
session, sends `hi`, logs in with the latest token and attaches the same topics again (`me`
first). Waits grow with full-jitter exponential backoff (random in `[0, min(cap, base·2^n))`), so
clients that dropped together don't return together. Nothing sent to you while you were away is
replayed: fetch the gap with `get data` and `since`.
*In this package:* `ReconnectPolicy`, `TinodeClient.resume`.
*Avoid:* "retry" for this; a retry is one more attempt within a reconnect.

**Connection status**
Where the client's link stands: `Connected`, `Reconnecting` (with the attempt and the wait),
`Suspended` (closed on purpose, e.g. in the background) or `Disconnected` (final: closed by the app,
or the server refused the session, such as an expired token).
*In this package:* `ConnectionStatus`, `TinodeClient.status` and `statusChanges`.

**Probe**
A bare `1` frame; the server answers `0`. Mobile networks can kill a socket without closing it, so
after a quiet spell the client probes, and a probe without any answer ends the socket. After the
OS reports a network change a dead socket is likely, so that probe can use a shorter deadline.
*In this package:* `TinodeConfig.probeAfter` and `probeTimeout`; `resume` probes a live link,
with its own `probeTimeout` if given.

**Lost topic**
An attached topic that the server refuses to attach again after a reconnect, e.g. because you
were removed meanwhile.
*In this package:* `Connected.lostTopics`, with the server's refusal.

---

## Server facts

**Endpoint**
`ws(s)://<host>/v0/channels?apikey=<key>` for the WebSocket. Files go through
`/v0/file/u` (upload) and `/v0/file/s` (download).

**Protocol version** (`ver`)
Sent in `hi`, e.g. `0.25`. The server replies with its own version and `build`.
*In this package:* `TinodeClient.protocolVersion`; the server's is `ServerInfo.version`.

**Server limits**
Returned in the `hi` reply, e.g. `maxMessageSize`, `maxFileUploadSize`, `maxSubscriberCount`,
`maxTagCount`, and for calls `iceServers` and `callTimeout`.
*In this package:* `ServerInfo`.

**Push notifications**
Delivered by the server through FCM or the Tinode push gateway, to a device token sent as `dev` in
`hi`.
