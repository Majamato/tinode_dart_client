import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import '../support/fake_server.dart';

TinodeConfig configFor(String server) => TinodeConfig(
  server: Uri.parse(server),
  apiKey: 'key',
  userAgent: 'test/1.0',
);

void main() {
  group('httpBase', () {
    test('maps ws to http and wss to https, keeping port and prefix', () {
      expect(
        configFor('ws://localhost:6060').httpBase.toString(),
        'http://localhost:6060',
      );
      expect(
        configFor('wss://host/chat/?x=1').httpBase.toString(),
        'https://host/chat',
      );
      expect(
        configFor('wss://host/chat').uploadUri.toString(),
        'https://host/chat/v0/file/u/',
      );
    });
  });

  group('resolveFile', () {
    final config = configFor('wss://host/chat');
    String resolve(String ref) => config.resolveFile(ref).toString();

    test('joins /v0/ refs to the base, keeping its prefix', () {
      expect(resolve('/v0/file/s/a.jpg'), 'https://host/chat/v0/file/s/a.jpg');
    });

    test('resolves bare refs against the file path', () {
      expect(resolve('a.jpg'), 'https://host/chat/v0/file/s/a.jpg');
    });

    test('keeps absolute http(s) refs', () {
      expect(resolve('http://cdn.example/a.jpg'), 'http://cdn.example/a.jpg');
      expect(resolve('https://host/x'), 'https://host/x');
    });

    test('refuses other schemes', () {
      for (final ref in ['javascript:alert(1)', 'file:///etc/passwd']) {
        expect(() => config.resolveFile(ref), throwsArgumentError);
        expect(config.tryResolveFile(ref), isNull);
      }
    });
  });

  group('attachmentPath', () {
    final config = configFor('wss://host/chat');

    test('is the server path of an upload on this server', () {
      expect(config.attachmentPath('/v0/file/s/a.jpg'), '/v0/file/s/a.jpg');
      expect(config.attachmentPath('a.jpg'), '/v0/file/s/a.jpg');
      expect(
        config.attachmentPath('https://host/chat/v0/file/s/a.jpg'),
        '/v0/file/s/a.jpg',
      );
    });

    test('is null for anything else', () {
      for (final ref in [
        'https://cdn.example/v0/file/s/a.jpg',
        'http://host/chat/v0/file/s/a.jpg',
        'https://host/chat/elsewhere/a.jpg',
        'mailto:a@b.c',
      ]) {
        expect(config.attachmentPath(ref), isNull, reason: ref);
      }
    });
  });

  group('extra.attachments', () {
    late FakeServer server;
    late TinodeClient client;

    setUp(() async {
      server = FakeServer();
      final connecting = TinodeClient.connect(
        configFor('ws://localhost:6060'),
        connector: (_) async => server.client,
      );
      await server.handshake();
      client = await connecting;
    });

    tearDown(() => client.close());

    test('a pub lists the uploads its content refers to, once', () async {
      const content = Drafty(
        text: ' ',
        spans: [Span(at: 0, length: 1)],
        entities: [
          Entity(type: 'IM', data: {'ref': '/v0/file/s/a.jpg'}),
          Entity(
            type: 'EX',
            data: {'ref': 'http://localhost:6060/v0/file/s/b.pdf'},
          ),
          Entity(type: 'EX', data: {'ref': '/v0/file/s/a.jpg'}),
          Entity(type: 'VD', data: {'ref': 'v.mp4', 'preref': 'v.jpg'}),
          Entity(type: 'IM', data: {'ref': 'https://cdn.example/c.jpg'}),
          Entity(type: 'LN', data: {'url': '/v0/file/s/link'}),
        ],
      );
      final published = client.publish('grpA', const DraftyContent(content));
      final packet = await server.nextPacket('pub');
      expect(packet['extra'], {
        'attachments': [
          '/v0/file/s/a.jpg',
          '/v0/file/s/b.pdf',
          '/v0/file/s/v.mp4',
          '/v0/file/s/v.jpg',
        ],
      });
      server.ctrl(packet['pub']! as Json, code: 202, params: {'seq': 1});
      await published;
    });

    test('plain text and foreign refs add no extra', () async {
      final published = client.publish('grpA', const PlainText('hi'));
      final packet = await server.nextPacket('pub');
      expect(packet, isNot(contains('extra')));
      server.ctrl(packet['pub']! as Json, code: 202, params: {'seq': 1});
      await published;

      final foreign = client.publish(
        'grpA',
        DraftyContent(
          Drafty.file(const DraftyFile(ref: 'https://cdn.example/a.pdf')),
        ),
      );
      final second = await server.nextPacket('pub');
      expect(second, isNot(contains('extra')));
      server.ctrl(second['pub']! as Json, code: 202, params: {'seq': 2});
      await foreign;
    });

    test('a set and a creating sub list the photo upload', () async {
      const public = Profile(
        name: 'Hikers',
        photo: ProfilePhoto(type: 'jpg', ref: '/v0/file/s/p.jpg'),
      );
      const expected = {
        'attachments': ['/v0/file/s/p.jpg'],
      };

      final set = client.setDescription('grpA', public: public);
      final setPacket = await server.nextPacket('set');
      expect(setPacket['extra'], expected);
      server.ctrl(setPacket['set']! as Json);
      await set;

      final created = client.createGroup(public: public);
      final subPacket = await server.nextPacket('sub');
      expect(subPacket['extra'], expected);
      server.ctrl(subPacket['sub']! as Json, topic: 'grpNew');
      expect(await created, 'grpNew');
    });
  });
}
