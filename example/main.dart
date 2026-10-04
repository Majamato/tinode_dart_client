// ignore_for_file: avoid_print, a console example.

// Logs in, lists the chats, sends a message to the first one and prints
// everything that arrives for 30 seconds.
//
// dart run example/main.dart [login] [password]
// The defaults target a local server started from the official Docker image.

import 'dart:async';

import 'package:tinode_dart_client/tinode_dart_client.dart';

Future<void> main(List<String> args) async {
  final login = args.isNotEmpty ? args[0] : 'alice';
  final password = args.length > 1 ? args[1] : '${login}123';

  final client = await TinodeClient.connect(
    TinodeConfig(
      server: Uri.parse('ws://localhost:6060'),
      apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
      userAgent: 'tinode_dart_client-example/0.1',
    ),
  );

  try {
    final session = await client.loginBasic(login, password);
    print(
      'Logged in as ${session.userId} (server ${client.serverInfo.version})',
    );

    client.events.listen(
      (packet) => switch (packet) {
        DataMessage(:final topic, :final seq, :final content) => print(
          '[$topic #$seq] ${content.text}',
        ),
        PresMessage(:final source, :final event) => print(
          'presence: $source ${event.name}',
        ),
        InfoMessage(:final from, :final event) => print(
          'info: $from ${event.name}',
        ),
        CtrlMessage() || MetaMessage() => null,
      },
      onError: (Object error) => print('ignored: $error'),
    );

    await client.subscribe('me');
    final chats = await client.getSubscriptions('me');
    for (final chat in chats) {
      print('${chat.topic}  ${chat.public?.name}  unread: ${chat.unread}');
    }
    if (chats.isEmpty) return;

    final topic = await client.subscribe(chats.first.topic!);
    final ack = await client.publish(
      topic,
      const PlainText('Hello from tinode_dart_client'),
    );
    print('Sent to $topic as #${ack.seq}');

    await Future<void>.delayed(const Duration(seconds: 30));
  } finally {
    await client.close();
  }
}
