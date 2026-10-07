/// A pure-Dart client for the [Tinode](https://github.com/tinode/chat) chat
/// server, speaking its JSON-over-WebSocket protocol.
library;

export 'src/client/connection_status.dart';
export 'src/client/connection_supervisor.dart' show SocketConnector;
export 'src/client/reconnect_policy.dart';
export 'src/client/results.dart';
export 'src/client/tinode_client.dart';
export 'src/client/tinode_config.dart';
export 'src/errors.dart';
export 'src/json/json_reader.dart' show Json;
export 'src/model/access_mode.dart';
export 'src/model/call.dart';
export 'src/model/drafty.dart';
export 'src/model/message_content.dart';
export 'src/model/message_head.dart';
export 'src/model/private_settings.dart';
export 'src/model/profile.dart';
export 'src/model/subscription.dart';
export 'src/model/topic_description.dart';
export 'src/model/topic_kind.dart';
export 'src/protocol/server/server_message.dart';
