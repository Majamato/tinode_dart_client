import 'dart:async';

import 'package:tinode_dart_client/src/client/connection_status.dart';
import 'package:tinode_dart_client/src/client/requests.dart';
import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/client/tinode_config.dart';
import 'package:tinode_dart_client/src/connection/backoff.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';
import 'package:web_socket/web_socket.dart';

/// Opens the WebSocket to the server's channels URI.
typedef SocketConnector = Future<WebSocket> Function(Uri uri);

/// Keeps the client connected across sessions: after a drop it opens a new
/// session with backoff, logs in again with the latest token and re-attaches
/// the old session's topics.
final class ConnectionSupervisor {
  ConnectionSupervisor._(this._config, this._connector)
    : _backoff = Backoff(
        base: _config.reconnect.base,
        cap: _config.reconnect.cap,
      );

  /// Connects once. Unlike later reconnects, a failure here throws.
  static Future<ConnectionSupervisor> open(
    TinodeConfig config,
    SocketConnector connector,
  ) async {
    final supervisor = ConnectionSupervisor._(config, connector);
    final (connection, info) = await supervisor._handshake();
    supervisor._adopt(connection, info);
    return supervisor;
  }

  final TinodeConfig _config;
  final SocketConnector _connector;
  final Backoff _backoff;
  final _events = StreamController<ServerMessage>.broadcast();
  final _statuses = StreamController<ConnectionStatus>.broadcast();
  Connection? _connection;
  StreamSubscription<ServerMessage>? _pipe;
  late ServerInfo _serverInfo;
  ConnectionStatus _status = const Connected();
  Timer? _retry;
  var _attempts = 0;

  /// Bumped whenever the link is torn down on purpose; a recovery that
  /// sees it change was overtaken and gives up.
  var _epoch = 0;

  /// The latest login token, for logging in again after a drop.
  String? token;

  /// Attached topics by their real names, restored after a drop.
  final attached = <String>{};

  ServerInfo get serverInfo => _serverInfo;
  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusChanges => _statuses.stream;
  Stream<ServerMessage> get events => _events.stream;

  /// The connection for the app's requests; null unless [Connected].
  Connection? get ready => _status is Connected ? _connection : null;

  /// Like [ready], but throws so requests fail fast while the link is down.
  Connection get connection =>
      ready ?? (throw const ConnectionClosedException('not connected'));

  void suspend() {
    if (_status case Suspended() || Disconnected()) return;
    unawaited(_stop());
    _setStatus(const Suspended());
  }

  /// Reconnects now, skipping any wait; probes a link that looks alive.
  void resume({Duration? probeTimeout}) {
    switch (_status) {
      case Connected():
        _connection?.probe(timeout: probeTimeout);
      case Reconnecting() || Suspended():
        unawaited(_stop());
        _backoff.reset();
        _schedule(null, Duration.zero);
      case Disconnected():
        break;
    }
  }

  Future<void> close() async {
    if (_status is Disconnected) return;
    await _shutDown(null);
  }

  /// Opens a socket and says `hi` on it.
  Future<(Connection, ServerInfo)> _handshake() async {
    final WebSocket socket;
    try {
      socket = await _connector(_config.channelsUri);
    } on Exception catch (e) {
      throw ServerUnreachableException(e);
    }
    // Held from the start, so a suspend or close mid-handshake ends it.
    final connection = _connection = Connection(
      socket,
      timeout: _config.requestTimeout,
      probeAfter: _config.probeAfter,
      probeTimeout: _config.probeTimeout,
    );
    try {
      return (connection, await connection.hello(_config));
    } on Object {
      await connection.close();
      rethrow;
    }
  }

  void _adopt(Connection connection, ServerInfo info) {
    _serverInfo = info;
    _pipe = connection.events.listen(_events.add, onError: _events.addError);
    unawaited(connection.done.then((cause) => _onDrop(connection, cause)));
  }

  void _onDrop(Connection connection, TinodeException cause) {
    // Drops during a recovery surface there, as failed requests.
    if (!identical(connection, _connection) || _status is! Connected) return;
    if (!_config.reconnect.enabled) {
      unawaited(_shutDown(cause));
      return;
    }
    unawaited(_stop());
    _schedule(cause, _backoff.next());
  }

  void _schedule(TinodeException? cause, Duration delay) {
    final epoch = _epoch;
    _setStatus(
      Reconnecting(attempt: ++_attempts, retryIn: delay, cause: cause),
    );
    _retry = Timer(delay, () => unawaited(_recover(epoch)));
  }

  Future<void> _recover(int epoch) async {
    try {
      final (connection, info) = await _handshake();
      if (epoch != _epoch) return connection.close();
      _adopt(connection, info);

      LoginResult? login;
      if (token case final token?) {
        login = await connection.login('token', token);
        this.token = login.token;
      }
      final lost = <String, ServerException>{};
      for (final topic in [
        if (attached.contains('me')) 'me',
        ...attached.where((t) => t != 'me'),
      ]) {
        try {
          await connection.attach(topic);
        } on ServerException catch (e) {
          lost[topic] = e;
          attached.remove(topic);
        }
      }
      if (epoch != _epoch) return;
      _backoff.reset();
      _attempts = 0;
      _setStatus(Connected(login: login, lostTopics: lost));
    } on TinodeException catch (e) {
      if (epoch != _epoch) return;
      // 4xx: the server refuses this session; 505: this protocol version.
      if (e is ServerException && (e.code < 500 || e.code == 505)) {
        return _shutDown(e);
      }
      await _stop();
      _schedule(e, _backoff.next());
    }
  }

  /// Ends the current socket and any pending retry, on purpose.
  Future<void> _stop() async {
    _epoch++;
    _retry?.cancel();
    unawaited(_pipe?.cancel());
    final connection = _connection;
    _connection = null;
    await connection?.close();
  }

  Future<void> _shutDown(TinodeException? cause) async {
    final stopped = _stop();
    _setStatus(Disconnected(cause: cause));
    unawaited(_statuses.close());
    unawaited(_events.close());
    await stopped;
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statuses.add(status);
  }
}
