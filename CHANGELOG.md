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
