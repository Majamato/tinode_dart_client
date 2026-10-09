import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/client/tinode_config.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';

/// Protocol version sent in `hi`.
const wireVersion = '0.25';

/// How often [Requests.attach] tries a topic the server reports as locked.
const attachAttempts = 4;

/// The wait before the second attach; later waits grow linearly.
const attachRetryDelay = Duration(milliseconds: 200);

/// The request/reply steps shared by the client and its reconnects.
extension Requests on Connection {
  /// Completes with the `ctrl` answering [message].
  Future<CtrlMessage> ctrl(ClientMessage message) async =>
      switch (await request(message)) {
        final CtrlMessage ctrl => ctrl,
        final other => throw MalformedPacketException(message.type, other),
      };

  Future<ServerInfo> hello(TinodeConfig config) async {
    final hi = Hi(
      ver: wireVersion,
      ua: config.userAgent,
      lang: config.language,
    );
    return ServerInfo.fromParams((await ctrl(hi)).params);
  }

  Future<LoginResult> login(String scheme, String secret) async =>
      LoginResult.fromParams(
        (await ctrl(Login(scheme: scheme, secret: secret))).params,
      );

  /// Returns the topic's real name. Retries `503 locked`, which the server
  /// sends while it loads the topic, e.g. when both sides of a P2P chat
  /// attach at once.
  Future<String> attach(
    String topic, {
    TopicChanges? init,
    List<String> attachments = const [],
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final sub = Sub(topic, init: init, attachments: attachments);
        return (await ctrl(sub)).topic ?? topic;
      } on ServerException catch (e) {
        if (e.code != 503 || attempt >= attachAttempts) rethrow;
        await Future<void>.delayed(attachRetryDelay * attempt);
      }
    }
  }
}
