# Notes: tinode_dart_client

Reminders from the October 2026 exploration that led to this package.
The sibling package `../tinode_flutter_chat` is the Flutter UI built on top of this one.

## Why this exists

- The only Dart package on pub.dev (`tinode`, 1.0.0-alpha.4) has been abandoned for about 5 years
  and keeps everything in memory only. Official Tinode clients exist for Android (Java),
  iOS (Swift) and Web (JS), but not for Dart.
- The protocol is small and plain JSON over WebSocket, so writing our own client is realistic.
  `../tinode-tests/ws_smoke_test.dart` does connect, log in, list contacts and send in about 100 lines.

## Server basics

- Go server, GPL-3.0 (official client SDKs are Apache-2.0). Self-hosted; local test setup in
  `../tinode-tests` (`docker compose up -d`, web UI at http://localhost:6060/).
- Endpoint: `ws://<host>:6060/v0/channels?apikey=<key>`. Demo key of the official images:
  `AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K` (generate your own for anything real).
- Sample users: `alice`, `bob`, `carol`, `dave`, `eve`, `frank`; password = name + `123`.
- Protocol reference: https://github.com/tinode/chat/blob/master/docs/API.md

## Protocol essentials

- Client packets: `hi`, `login`, `acc`, `sub`, `leave`, `pub`, `get`, `set`, `del`, `note`.
  Each carries an `id`; the server answers with a `{ctrl}` packet that has the same `id`.
- Server packets: `ctrl` (replies), `data` (messages), `meta` (topic info, contact lists),
  `pres` (presence/updates), `info` (typing, read and received notifications).
- `login` with scheme `basic`: secret = base64 of `user:password`.
- Topic names: `me` (own account and contact list), `fnd` (search), `usr…` (1:1),
  `grp…` (group), `chn…` (a group's channel, read-only access).
- Message content is "Drafty": a plain string or JSON with the text in `txt`.

## Offline sync (to build)

- Messages are numbered per topic with `seq`. Keep the highest seq stored locally and
  fetch gaps with `get data` using `since` / `before`.
- Deletions: every delete gets a delete ID; the latest one comes back as `clear`. Fetch the
  ranges you missed with `get del` using `since`.
- Queue messages written while offline as "pending" and send them on reconnect
  (Tindroid does this with a `status` column).
- Local store: SQLite with the `sqlite3` / `drift` packages, which bundle their own SQLite with FTS5.
  Avoid `sqflite` + the phone's built-in SQLite if you need full-text search.

## Search

- The server has NO message full-text search (issue #675, open since 2021, no one working on it).
  `fnd` only finds users and topics by tags (space = AND, comma = OR).
- Plan: local FTS5 index over the plain text of messages (Drafty `txt`, not the raw JSON).
  Only finds what's stored on the device; keep it updated on edits and deletes.

## Risks to keep in mind

- One main maintainer (`or-else`) wrote almost all of the server. It's active (v0.25.3, Jul 2026),
  and paid support is available from Tinode LLC, but there's no deep bench.
- The server's push code uses the legacy Firebase Admin SDK v3 for FCM topic subscriptions,
  which only affects followers of channels. That service stops on 2027-09-29.
  1:1 and group pushes use FCM HTTP v1 and aren't affected.
