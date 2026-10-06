import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// Where the client's link to the server stands. Messages sent while it
/// was down are not replayed: after a reconnect, fetch them by seq.
sealed class ConnectionStatus with ValueObject {
  const ConnectionStatus();
}

/// Requests can be made. After a reconnect, [login] is the client's own
/// token login: every login renews the token's expiry, so keep the newest.
final class Connected extends ConnectionStatus {
  const Connected({this.login, this.lostTopics = const {}});

  final LoginResult? login;

  /// Topics that could not be attached again, with the server's refusal.
  final Map<String, ServerException> lostTopics;

  @override
  List<Object?> get props => [login, lostTopics];
}

/// The link dropped; the next attempt starts after [retryIn].
final class Reconnecting extends ConnectionStatus {
  const Reconnecting({
    required this.attempt,
    required this.retryIn,
    this.cause,
  });

  /// 1 for the first retry after a drop.
  final int attempt;
  final Duration retryIn;
  final TinodeException? cause;

  @override
  List<Object?> get props => [attempt, retryIn, cause];
}

/// Closed on purpose by `suspend`; `resume` restores the session.
final class Suspended extends ConnectionStatus {
  const Suspended();

  @override
  List<Object?> get props => const [];
}

/// Final: closed by the app, or the server refused the session (e.g. an
/// expired token, code 401). [cause] is null for a close by the app.
final class Disconnected extends ConnectionStatus {
  const Disconnected({this.cause});

  final TinodeException? cause;

  @override
  List<Object?> get props => [cause];
}
