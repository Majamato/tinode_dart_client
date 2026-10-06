import 'package:meta/meta.dart';
import 'package:tinode_dart_client/src/client/reconnect_policy.dart';

@immutable
final class TinodeConfig {
  const TinodeConfig({
    required this.server,
    required this.apiKey,
    required this.userAgent,
    this.language,
    this.requestTimeout = const Duration(seconds: 10),
    this.reconnect = const ReconnectPolicy(),
    this.probeAfter = const Duration(seconds: 25),
    this.probeTimeout = const Duration(seconds: 10),
  });

  /// Base WebSocket URL of the server, e.g. `wss://chat.example.com`.
  final Uri server;

  /// Sent as a query parameter: browsers cannot set WebSocket headers.
  final String apiKey;

  /// Identifies the app to the server and to peers, e.g. `MyApp/1.0`.
  final String userAgent;

  /// Language tag such as `en-US`, used by the server for push texts.
  final String? language;
  final Duration requestTimeout;
  final ReconnectPolicy reconnect;

  /// Silence after which the client probes the server, null to never
  /// probe on its own. Mobile networks drop sockets without closing them.
  final Duration? probeAfter;

  /// How long a probe may go unanswered before the socket counts as dead.
  final Duration probeTimeout;

  Uri get channelsUri => server.replace(
    path: '${server.path.replaceFirst(RegExp(r'/+$'), '')}/v0/channels',
    queryParameters: {...server.queryParameters, 'apikey': apiKey},
  );
}
