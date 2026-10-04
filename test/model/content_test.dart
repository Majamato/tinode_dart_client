import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

void main() {
  group('MessageContent', () {
    test('a string is plain text', () {
      expect(MessageContent.fromJson('hi'), const PlainText('hi'));
    });

    test('an object is Drafty, with zero values defaulted', () {
      final content = MessageContent.fromJson({
        'txt': 'bold link',
        'fmt': [
          {'len': 4, 'tp': 'ST'},
          {'at': 5, 'len': 4},
        ],
        'ent': [
          {
            'tp': 'LN',
            'data': {'url': 'https://tinode.co'},
          },
        ],
      });
      expect(content.text, 'bold link');
      final drafty = (content as DraftyContent).drafty;
      expect(drafty.spans, const [
        Span(at: 0, length: 4, style: 'ST'),
        Span(at: 5, length: 4, entityIndex: 0),
      ]);
      expect(drafty.entities.single.data['url'], 'https://tinode.co');
    });

    test('malformed Drafty parts are dropped, not fatal', () {
      final content = MessageContent.fromJson({
        'txt': 42,
        'fmt': ['x', 7],
        'ent': [<String, Object?>{}],
      });
      expect(content, const DraftyContent(Drafty(text: '')));
    });

    test('anything else is kept as unknown', () {
      for (final raw in [
        3,
        null,
        true,
        <Object?>['a'],
      ]) {
        final content = MessageContent.fromJson(raw);
        expect(content, UnknownContent(raw));
        expect(content.text, isEmpty);
        expect(content.toJson(), raw);
      }
    });

    test('Drafty serialises back without default values', () {
      const drafty = Drafty(
        text: 'bold link',
        spans: [
          Span(at: 0, length: 4, style: 'ST'),
          Span(at: 5, length: 4, entityIndex: 0),
        ],
        entities: [
          Entity(type: 'LN', data: {'url': 'https://tinode.co'}),
        ],
      );
      expect(drafty.toJson(), {
        'txt': 'bold link',
        'fmt': [
          {'len': 4, 'tp': 'ST'},
          {'at': 5, 'len': 4},
        ],
        'ent': [
          {
            'tp': 'LN',
            'data': {'url': 'https://tinode.co'},
          },
        ],
      });
      expect(Drafty.fromJson(drafty.toJson()), drafty);
    });
  });

  group('Profile', () {
    test('keeps unknown keys in raw and ignores wrong types', () {
      final profile = Profile.fromJson({
        'fn': 'Alice',
        'note': 5,
        'photo': {'type': 'jpg', 'ref': '/v0/file/s/a.jpg'},
        'x-example-com-role': 'admin',
      });
      expect(profile.name, 'Alice');
      expect(profile.note, isNull);
      expect(
        profile.photo,
        const ProfilePhoto(type: 'jpg', ref: '/v0/file/s/a.jpg'),
      );
      expect(profile.raw['x-example-com-role'], 'admin');
    });

    test('an empty object or a non-object photo gives no fields', () {
      expect(Profile.fromJson({}), const Profile());
      expect(Profile.fromJson({'photo': 'a.jpg'}).photo, isNull);
    });

    test('tryParse reads only objects', () {
      expect(
        Profile.tryParse({'fn': 'Alice'}),
        const Profile(name: 'Alice', raw: {'fn': 'Alice'}),
      );
      for (final value in [
        null,
        3,
        <Object?>['Alice'],
      ]) {
        expect(Profile.tryParse(value), isNull);
      }
    });

    test('tryParse skips the query string fnd keeps in public', () {
      expect(Profile.tryParse('alice, bob'), isNull);
    });
  });

  group('PrivateSettings', () {
    test('reads the conventional keys and keeps the rest in raw', () {
      final settings = PrivateSettings.fromJson({
        'comment': 'from work',
        'arch': true,
        'accepted': 'JRWP',
        'tpins': ['usrB', 7, 'grpC'],
        'x-example-com-color': 'blue',
      });
      expect(settings.comment, 'from work');
      expect(settings.archived, isTrue);
      expect(settings.accepted, AccessMode.parse('JRWP'));
      expect(settings.pinnedTopics, ['usrB', 'grpC']);
      expect(settings.raw['x-example-com-color'], 'blue');
    });

    test('wrong types fall back to defaults', () {
      final settings = PrivateSettings.fromJson({'arch': 'yes', 'tpins': 3});
      expect(settings.archived, isFalse);
      expect(settings.pinnedTopics, isEmpty);
    });
  });

  group('TopicKind', () {
    test('derives the kind from the name', () {
      const kinds = {
        'me': TopicKind.account,
        'fnd': TopicKind.search,
        'slf': TopicKind.notes,
        'sys': TopicKind.system,
        'usrS8SZdtb3xS0': TopicKind.direct,
        'p2pS8SZdtb3xS0': TopicKind.direct,
        'grpmiKBkQVXnm3P': TopicKind.group,
        'new': TopicKind.group,
        'newKBkQVXnm3P': TopicKind.group,
        'chnmiKBkQVXnm3P': TopicKind.channel,
        'nch': TopicKind.channel,
        'zzz': TopicKind.unknown,
        '': TopicKind.unknown,
      };
      for (final MapEntry(key: name, value: kind) in kinds.entries) {
        expect(TopicKind.of(name), kind, reason: name);
      }
    });

    test('the fixed names match exactly', () {
      expect(TopicKind.of('mee'), TopicKind.unknown);
      expect(TopicKind.of('fndx'), TopicKind.unknown);
    });
  });
}
