import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/client/tinode_config.dart';
import 'package:tinode_dart_client/src/connection/connection.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/protocol/client/client_message.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';

/// Protocol version sent in `hi`.
const wireVersion = '0.25';

/// The code of a reply that wants credentials confirmed.
const credentialsCode = 300;

/// The value that clears a field, e.g. the device token in `hi`.
const clearValue = '\u2421';

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

  /// The first `hi` of a session, with the push [device] token if any:
  /// the server registers it for the user who logs in next.
  Future<ServerInfo> hello(TinodeConfig config, {String? device}) async =>
      ServerInfo.fromParams((await ctrl(_hi(config, device))).params);

  /// A later `hi`, allowed once logged in: replaces the session's push
  /// device token, or with null removes it. The server also takes `ua`
  /// and `lang` from it again, so they are repeated.
  Future<void> updateDevice(TinodeConfig config, String? device) =>
      ctrl(_hi(config, device ?? clearValue));

  /// Code 300, credentials to confirm, throws
  /// [CredentialsRequiredException].
  Future<LoginResult> login(
    String scheme,
    String secret, {
    Map<String, String> codes = const {},
  }) async => LoginResult.fromParams(
    (await ctrlOrCredentials(
      Login(scheme: scheme, secret: secret, codes: codes),
    )).params,
  );

  /// Like [ctrl], with code 300 as [CredentialsRequiredException].
  Future<CtrlMessage> ctrlOrCredentials(ClientMessage message) async {
    try {
      return await ctrl(message);
    } on ServerException catch (e) {
      if (e.code != credentialsCode) rethrow;
      throw CredentialsRequiredException([
        ...?(e.params['cred'] as List<Object?>?)?.whereType<String>(),
      ], userId: e.params['user'] as String?);
    }
  }

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

Hi _hi(TinodeConfig config, String? device) => Hi(
  ver: wireVersion,
  ua: config.userAgent,
  lang: config.language,
  dev: device,
  platf: config.platform?.name,
);
