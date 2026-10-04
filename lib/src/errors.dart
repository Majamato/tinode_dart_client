import 'package:tinode_dart_client/src/json/json_reader.dart';

sealed class TinodeException implements Exception {
  const TinodeException();
}

/// The server rejected a request; [code] follows HTTP semantics.
final class ServerException extends TinodeException {
  const ServerException(this.code, this.text, {this.params = const {}});

  final int code;
  final String text;
  final Json params;

  @override
  String toString() => 'ServerException($code $text)';
}

/// The connection ended while a request was waiting for its reply.
final class ConnectionClosedException extends TinodeException {
  const ConnectionClosedException([this.reason = '']);

  final String reason;

  @override
  String toString() => 'ConnectionClosedException($reason)';
}

/// No reply arrived within the configured request timeout.
final class RequestTimeoutException extends TinodeException {
  const RequestTimeoutException(this.request, this.timeout);

  final String request;
  final Duration timeout;

  @override
  String toString() => 'RequestTimeoutException($request after $timeout)';
}

/// A server packet did not match the protocol at [path].
final class MalformedPacketException extends TinodeException {
  const MalformedPacketException(this.path, this.value);

  final String path;
  final Object? value;

  @override
  String toString() => 'MalformedPacketException($path: $value)';
}
