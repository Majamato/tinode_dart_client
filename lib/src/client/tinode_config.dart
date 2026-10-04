import 'package:meta/meta.dart';

@immutable
final class TinodeConfig {
  const TinodeConfig({
    required this.server,
    required this.apiKey,
    required this.userAgent,
    this.language,
    this.requestTimeout = const Duration(seconds: 10),
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

  Uri get channelsUri => server.replace(
    path: '${server.path}/v0/channels',
    queryParameters: {...server.queryParameters, 'apikey': apiKey},
  );
}
