import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// The server's reply to `hi`: its version and limits.
final class ServerInfo with ValueObject {
  const ServerInfo({
    required this.version,
    this.build,
    this.maxMessageSize,
    this.maxFileUploadSize,
    this.iceServers = const [],
    this.callTimeout,
    this.raw = const {},
  });

  factory ServerInfo.fromParams(Json params) {
    final j = LooseJson(params);
    final callTimeout = j.get<int>('callTimeout');
    return ServerInfo(
      version: j.get('ver') ?? '',
      build: j.get('build'),
      maxMessageSize: j.get('maxMessageSize'),
      maxFileUploadSize: j.get('maxFileUploadSize'),
      iceServers: [
        for (final item in j.get<List<Object?>>('iceServers') ?? const [])
          if (item case final Json server) ?IceServer._tryParse(server),
      ],
      callTimeout: callTimeout == null ? null : Duration(seconds: callTimeout),
      raw: params,
    );
  }

  /// What the client knows before its first `hi` is answered, e.g. after
  /// `TinodeClient.restore`: no limits and no calls.
  static const unknown = ServerInfo(version: '');

  final String version;
  final String? build;
  final int? maxMessageSize;
  final int? maxFileUploadSize;

  /// The STUN/TURN servers to give WebRTC for calls.
  final List<IceServer> iceServers;

  /// How long the server lets a call ring before ending it as missed.
  final Duration? callTimeout;

  /// All params, including limits not typed here.
  final Json raw;

  /// The server only takes calls when it has ICE servers to hand out.
  bool get callsEnabled => iceServers.isNotEmpty;

  @override
  List<Object?> get props => [
    version,
    build,
    maxMessageSize,
    maxFileUploadSize,
    iceServers,
    callTimeout,
    raw,
  ];
}

/// A STUN or TURN server for WebRTC; the fields match `RTCIceServer`.
final class IceServer with ValueObject {
  const IceServer({
    required this.urls,
    this.username,
    this.credential,
    this.credentialType,
  });

  /// `urls` may also be a single string, as WebRTC allows; a server without
  /// any is dropped.
  static IceServer? _tryParse(Json json) {
    final j = LooseJson(json);
    final urls = switch (json['urls']) {
      final String url => [url],
      final List<Object?> list => list.whereType<String>().toList(),
      _ => const <String>[],
    };
    if (urls.isEmpty) return null;
    return IceServer(
      urls: urls,
      username: j.get('username'),
      credential: j.get('credential'),
      credentialType: j.get('credential_type'),
    );
  }

  final List<String> urls;
  final String? username;
  final String? credential;

  /// `credential_type` on the wire; WebRTC calls it `credentialType`.
  final String? credentialType;

  @override
  List<Object?> get props => [urls, username, credential, credentialType];
}

/// A successful login. Reuse [token] with `loginToken` until [expires].
final class LoginResult with ValueObject {
  const LoginResult({required this.userId, required this.token, this.expires});

  factory LoginResult.fromParams(Json params) {
    final r = StrictJson(params);
    return LoginResult(
      userId: r.require('user', 'ctrl.params'),
      token: r.require('token', 'ctrl.params'),
      expires: r.optionalTime('expires', 'ctrl.params'),
    );
  }

  final String userId;
  final String token;
  final DateTime? expires;

  @override
  List<Object?> get props => [userId, token, expires];
}

/// The server accepted a message and numbered it [seq].
final class PublishResult with ValueObject {
  const PublishResult({required this.seq, required this.time});

  final int seq;
  final DateTime time;

  @override
  List<Object?> get props => [seq, time];
}

/// A file the server took. [ref] goes into a Drafty entity or a profile
/// photo; a message must refer to it before [expires], or the server may
/// delete it. [expires] is on this device's clock: the lifetime the server
/// gave the upload, counted from when its reply arrived.
final class UploadResult with ValueObject {
  const UploadResult({required this.ref, this.expires});

  final String ref;
  final DateTime? expires;

  @override
  List<Object?> get props => [ref, expires];
}

/// A file on its way from the server. [bytes] can be listened to once.
final class FileDownload {
  const FileDownload({
    required this.bytes,
    this.length,
    this.mimeType,
    this.etag,
  });

  final Stream<List<int>> bytes;

  /// The size in bytes, when the server sends it.
  final int? length;
  final String? mimeType;
  final String? etag;
}
