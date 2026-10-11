@Tags(['integration'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against a Tinode server with the sample data (users alice and bob).
final config = TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
  userAgent: 'tinode_dart_client-test/0.1',
);

Future<(TinodeClient, String)> loginAs(String user) async {
  final client = await TinodeClient.connect(config);
  addTearDown(client.close);
  return (client, (await client.loginBasic(user, '${user}123')).userId);
}

void main() {
  test('alice sends bob a file, and bob downloads it', () async {
    final (alice, aliceId) = await loginAs('alice');
    final (bob, bobId) = await loginAs('bob');
    await alice.subscribe(bobId);
    await bob.subscribe(aliceId);

    final bytes = utf8.encode('attachment ${DateTime.now()}');
    final upload = await alice.upload(
      () => Stream.value(bytes),
      length: bytes.length,
      filename: 'note.txt',
      mimeType: 'text/plain',
    );
    expect(upload.ref, startsWith('/v0/file/s/'));
    expect(upload.expires, isNotNull);

    final received = bob.messages.firstWhere(
      (m) => m.from == aliceId && m.content is DraftyContent,
    );
    await alice.publish(
      bobId,
      DraftyContent(
        Drafty.file(
          DraftyFile(
            mimeType: 'text/plain',
            name: 'note.txt',
            size: bytes.length,
            ref: upload.ref,
          ),
          caption: 'a note',
        ),
      ),
    );
    final message = await received;
    final drafty = (message.content as DraftyContent).drafty;
    expect(drafty.caption, 'a note');
    final file = drafty.files.single;
    expect(file.name, 'note.txt');

    final download = await bob.download(file.ref!);
    expect(await http.ByteStream(download.bytes).toBytes(), bytes);
    expect(download.mimeType, startsWith('text/plain'));
  });

  test('a download without a login fails with 401', () async {
    final (alice, _) = await loginAs('alice');
    final bytes = utf8.encode('secret');
    final upload = await alice.upload(
      () => Stream.value(bytes),
      length: bytes.length,
      filename: 'secret.txt',
    );

    final response = await http.get(
      config.resolveFile(upload.ref),
      headers: {'X-Tinode-APIKey': config.apiKey},
    );
    expect(response.statusCode, 401);
  });
}
