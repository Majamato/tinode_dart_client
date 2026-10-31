import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

Drafty parse(String json) => Drafty.fromJson(jsonDecode(json) as Json);

void main() {
  group('TinodeWeb samples', () {
    test('an image with a caption', () {
      final drafty = parse('''
        {"txt": "  Look!",
         "fmt": [{"len": 1}, {"at": 1, "len": 1, "tp": "BR"}],
         "ent": [{"tp": "IM", "data": {"mime": "image/jpeg",
           "ref": "/v0/file/s/abc.jpg", "width": 640, "height": 480,
           "name": "photo.jpg", "size": 51234}}]}''');

      expect(drafty.images, [
        const DraftyImage(
          mimeType: 'image/jpeg',
          ref: '/v0/file/s/abc.jpg',
          width: 640,
          height: 480,
          name: 'photo.jpg',
          size: 51234,
        ),
      ]);
      expect(drafty.files, isEmpty);
      expect(drafty.caption, 'Look!');
    });

    test('an inline image alone', () {
      final drafty = parse('''
        {"txt": " ", "fmt": [{"len": 1}],
         "ent": [{"tp": "IM", "data": {"mime": "image/png",
           "val": "AQID", "width": 1, "height": 1}}]}''');

      expect(drafty.images.single.bytes, [1, 2, 3]);
      expect(drafty.images.single.ref, isNull);
      expect(drafty.caption, isEmpty);
    });

    test('a file attachment with text', () {
      final drafty = parse('''
        {"txt": "the report",
         "fmt": [{"at": -1, "len": 0, "key": 0}],
         "ent": [{"tp": "EX", "data": {"mime": "application/pdf",
           "ref": "/v0/file/s/r.pdf", "name": "report.pdf", "size": 999}}]}''');

      expect(drafty.files, [
        const DraftyFile(
          mimeType: 'application/pdf',
          ref: '/v0/file/s/r.pdf',
          name: 'report.pdf',
          size: 999,
        ),
      ]);
      expect(drafty.spans.single.at, -1);
      expect(drafty.caption, 'the report');
    });

    test('a voice message, as tinode-js writes it', () {
      final drafty = parse('''
        {"txt": " ", "fmt": [{"at": 0, "len": 1, "key": 0}],
         "ent": [{"tp": "AU", "data": {"mime": "audio/mp4",
           "ref": "/v0/file/s/v.m4a", "duration": 4200, "preview": "AGRk",
           "name": "voice.m4a", "size": 9000}}]}''');

      expect(drafty.files, [
        DraftyAudio(
          mimeType: 'audio/mp4',
          ref: '/v0/file/s/v.m4a',
          name: 'voice.m4a',
          size: 9000,
          duration: const Duration(milliseconds: 4200),
          preview: Uint8List.fromList([0, 100, 100]),
        ),
      ]);
      expect(drafty.caption, isEmpty);
    });

    test('audio and video read as files', () {
      final drafty = parse('''
        {"txt": "", "fmt": [{"at": -1}, {"at": -1, "key": 1}],
         "ent": [{"tp": "AU", "data": {"mime": "audio/webm", "ref": "a"}},
                 {"tp": "VD", "data": {"mime": "video/mp4", "ref": "v"}}]}''');

      expect(drafty.files.map((f) => f.ref), ['a', 'v']);
      expect(drafty.images, isEmpty);
    });

    test('line breaks in a caption become newlines', () {
      final drafty = parse('''
        {"txt": "one two", "fmt": [{"at": 3, "len": 1, "tp": "BR"}]}''');
      expect(drafty.caption, 'one\ntwo');
    });
  });

  group('lenient reads', () {
    test('wrong types and bad base64 give nulls', () {
      final drafty = parse('''
        {"txt": " ", "fmt": [{"len": 1}],
         "ent": [{"tp": "IM", "data": {"mime": 7, "val": "not base64!",
           "width": "wide", "height": 2.0, "size": "big"}}]}''');

      final image = drafty.images.single;
      expect(image.mimeType, isNull);
      expect(image.bytes, isNull);
      expect(image.width, isNull);
      expect(image.height, 2);
      expect(image.size, isNull);
    });

    test('spans pointing nowhere are skipped', () {
      final drafty = parse('''
        {"txt": " ", "fmt": [{"len": 1, "key": 5}],
         "ent": [{"tp": "IM", "data": {}}]}''');
      expect(drafty.images, isEmpty);
      expect(drafty.caption, ' '.trim());
    });

    test('a voice message with wrong types keeps what it can', () {
      final drafty = parse('''
        {"txt": " ", "fmt": [{"len": 1}],
         "ent": [{"tp": "AU", "data": {"mime": "audio/mp4", "ref": "v",
           "duration": "long", "preview": "not base64!"}}]}''');

      final audio = drafty.files.single as DraftyAudio;
      expect(audio.ref, 'v');
      expect(audio.duration, isNull);
      expect(audio.preview, isNull);
    });

    test('a negative duration is unknown', () {
      final audio =
          const Entity(type: 'AU', data: {'duration': -5}).asFile!
              as DraftyAudio;
      expect(audio.duration, isNull);
    });

    test('other entities are neither images nor files', () {
      const link = Entity(type: 'LN', data: {'url': 'https://x'});
      expect(link.asImage, isNull);
      expect(link.asFile, isNull);
      const image = Entity(type: 'IM');
      expect(image.asFile, isNull);
    });
  });

  group('builders', () {
    const image = DraftyImage(
      mimeType: 'image/jpeg',
      ref: '/v0/file/s/abc.jpg',
      width: 640,
      height: 480,
      name: 'photo.jpg',
      size: 51234,
    );

    test('an image alone is a space under the image', () {
      expect(Drafty.image(image).toJson(), {
        'txt': ' ',
        'fmt': [
          {'len': 1},
        ],
        'ent': [
          {'tp': 'IM', 'data': image.toData()},
        ],
      });
    });

    test('an image with a caption adds a line break and the text', () {
      final drafty = Drafty.image(image, caption: 'Look!');
      expect(drafty.text, '  Look!');
      expect(drafty.toJson()['fmt'], [
        {'len': 1},
        {'at': 1, 'len': 1, 'tp': 'BR'},
      ]);
      expect(drafty.caption, 'Look!');
    });

    test('a file sits at -1 below its caption', () {
      const file = DraftyFile(mimeType: 'text/plain', ref: 'a.txt', size: 5);
      final drafty = Drafty.file(file, caption: 'notes');
      expect(drafty.toJson(), {
        'txt': 'notes',
        'fmt': [
          {'at': -1},
        ],
        'ent': [
          {
            'tp': 'EX',
            'data': {'mime': 'text/plain', 'size': 5, 'ref': 'a.txt'},
          },
        ],
      });
    });

    test('a voice message is a space marked as audio', () {
      final audio = DraftyAudio(
        mimeType: 'audio/mp4',
        ref: '/v0/file/s/v.m4a',
        name: 'voice.m4a',
        size: 9000,
        duration: const Duration(milliseconds: 4200),
        preview: Uint8List.fromList([0, 100, 100]),
      );
      expect(Drafty.audio(audio).toJson(), {
        'txt': ' ',
        'fmt': [
          {'len': 1},
        ],
        'ent': [
          {
            'tp': 'AU',
            'data': {
              'mime': 'audio/mp4',
              'name': 'voice.m4a',
              'size': 9000,
              'ref': '/v0/file/s/v.m4a',
              'duration': 4200,
              'preview': 'AGRk',
            },
          },
        ],
      });
      expect(Drafty.audio(audio).caption, isEmpty);
    });

    test('round-trip through JSON', () {
      for (final drafty in [
        Drafty.audio(
          DraftyAudio(
            ref: 'v',
            duration: const Duration(seconds: 3),
            preview: Uint8List.fromList([1, 50, 100]),
          ),
        ),
        Drafty.image(image),
        Drafty.image(image, caption: 'Look!'),
        Drafty.file(const DraftyFile(name: 'a', inlineData: 'AQID')),
      ]) {
        final again = Drafty.fromJson(
          jsonDecode(jsonEncode(drafty.toJson())) as Json,
        );
        expect(again, drafty);
        expect(again.images, drafty.images);
        expect(again.files, drafty.files);
      }
    });
  });
}
