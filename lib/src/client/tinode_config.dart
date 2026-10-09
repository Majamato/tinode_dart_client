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
    path: '$_prefix/v0/channels',
    queryParameters: {...server.queryParameters, 'apikey': apiKey},
  );

  /// The server over HTTP: `ws` becomes `http` and `wss` `https`, with the
  /// same host, port and path prefix, and no query.
  Uri get httpBase => Uri(
    scheme: switch (server.scheme) {
      'ws' => 'http',
      'wss' => 'https',
      final other => other,
    },
    host: server.host,
    port: server.hasPort ? server.port : null,
    path: _prefix,
  );

  /// Where files are uploaded.
  Uri get uploadUri => httpBase.replace(path: '$_prefix$_uploadPath');

  /// The URL of a file [ref] from a Drafty entity or a profile photo:
  ///
  /// - `/v0/…` refs, as uploads return them, are joined to [httpBase],
  ///   keeping its path prefix;
  /// - other relative refs resolve against `<httpBase>/v0/file/s/`;
  /// - absolute `http` and `https` refs stay as they are.
  ///
  /// Other schemes, such as `javascript:` or `file:`, throw
  /// [ArgumentError].
  Uri resolveFile(String ref) =>
      tryResolveFile(ref) ??
      (throw ArgumentError.value(ref, 'ref', 'is not an http(s) URL'));

  /// Like [resolveFile], but null for refs it refuses.
  Uri? tryResolveFile(String ref) {
    final uri = Uri.tryParse(ref);
    if (uri == null) return null;
    if (uri.hasScheme) {
      return uri.isScheme('http') || uri.isScheme('https') ? uri : null;
    }
    if (uri.hasAuthority) return httpBase.resolveUri(uri);
    if (uri.path.startsWith('/v0/')) {
      return httpBase.replace(
        path: '$_prefix${uri.path}',
        query: uri.hasQuery ? uri.query : null,
      );
    }
    return httpBase.replace(path: '$_prefix$_servePath').resolveUri(uri);
  }

  /// Whether [url] is on this server, so it may receive credentials.
  bool isOwnOrigin(Uri url) {
    final base = httpBase;
    return url.scheme == base.scheme &&
        url.host == base.host &&
        url.port == base.port;
  }

  /// The path the server names an upload by, e.g. `/v0/file/s/abc.jpg`, for
  /// a [ref] to a file uploaded to this server; null for any other ref.
  /// This is what `extra.attachments` lists.
  String? attachmentPath(String ref) {
    final url = tryResolveFile(ref);
    final served = '$_prefix$_servePath';
    if (url == null ||
        !isOwnOrigin(url) ||
        !url.path.startsWith(served) ||
        url.path.length == served.length) {
      return null;
    }
    return url.path.substring(_prefix.length);
  }

  static const _uploadPath = '/v0/file/u/';
  static const _servePath = '/v0/file/s/';

  /// The server's path prefix, without a trailing slash.
  String get _prefix => server.path.replaceFirst(RegExp(r'/+$'), '');
}
