import 'package:meta/meta.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/call.dart';
import 'package:tinode_dart_client/src/model/delete_log.dart';
import 'package:tinode_dart_client/src/model/message_content.dart';
import 'package:tinode_dart_client/src/model/message_head.dart';
import 'package:tinode_dart_client/src/model/subscription.dart';
import 'package:tinode_dart_client/src/model/topic_description.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

part 'ctrl_message.dart';
part 'data_message.dart';
part 'info_message.dart';
part 'meta_message.dart';
part 'pres_message.dart';

/// A packet sent by the server.
sealed class ServerMessage with ValueObject {
  const ServerMessage();

  /// Parses a decoded packet. Returns `null` for packet types this
  /// client does not know, so newer servers do not break it.
  @internal
  static ServerMessage? fromPacket(String key, Json value) {
    return switch (key) {
      'ctrl' => CtrlMessage._fromJson(value),
      'data' => DataMessage._fromJson(value),
      'meta' => MetaMessage._fromJson(value),
      'pres' => PresMessage._fromJson(value),
      'info' => InfoMessage._fromJson(value),
      _ => null,
    };
  }

  /// The topic the packet is about; absent only on some `ctrl` replies.
  String? get topic;
}
