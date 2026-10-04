import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// The server's reply to `hi`: its version and limits.
final class ServerInfo with ValueObject {
  const ServerInfo({
    required this.version,
    this.build,
    this.maxMessageSize,
    this.maxFileUploadSize,
    this.raw = const {},
  });

  factory ServerInfo.fromParams(Json params) {
    final j = LooseJson(params);
    return ServerInfo(
      version: j.get('ver') ?? '',
      build: j.get('build'),
      maxMessageSize: j.get('maxMessageSize'),
      maxFileUploadSize: j.get('maxFileUploadSize'),
      raw: params,
    );
  }

  final String version;
  final String? build;
  final int? maxMessageSize;
  final int? maxFileUploadSize;

  /// All params, including limits not typed here.
  final Json raw;

  @override
  List<Object?> get props => [
    version,
    build,
    maxMessageSize,
    maxFileUploadSize,
    raw,
  ];
}

/// A successful login. Reuse [token] with `loginToken` until [expires].
final class LoginResult with ValueObject {
  const LoginResult({required this.userId, required this.token, this.expires});

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
