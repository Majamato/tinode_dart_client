import 'dart:convert';

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

/// Through a string as a store would keep it, so only JSON types survive.
Json viaText(Json json) => jsonDecode(jsonEncode(json)) as Json;

void main() {
  group('round trips', () {
    test('a data message with a Drafty call head', () {
      final message = DataMessage.fromJson(const {
        'topic': 'usrB',
        'from': 'usrA',
        'seq': 12,
        'ts': '2026-10-04T11:31:06.056Z',
        'head': {
          'mime': 'text/x-drafty',
          'webrtc': 'finished',
          'webrtc-duration': 6000,
          'replace': ':10',
          'x-app-cid': 'abc',
        },
        'content': {
          'txt': ' ',
          'fmt': [
            {'at': 0, 'len': 1, 'key': 0},
          ],
          'ent': [
            {'tp': 'VC'},
          ],
        },
      });
      expect(DataMessage.fromJson(viaText(message.toJson())), message);
    });

    test('plain, server-sent and unknown content', () {
      for (final content in <Object?>[
        'hi',
        {'odd': true},
        42,
      ]) {
        final message = DataMessage.fromJson({
          'topic': 'grpX',
          'seq': 1,
          'ts': '2026-10-04T11:31:06Z',
          'content': content,
        });
        expect(
          DataMessage.fromJson(viaText(message.toJson())),
          message,
          reason: '$content',
        );
      }
    });

    test('a chat with every field', () {
      final chat = Subscription.fromJson(const {
        'topic': 'usrB',
        'updated': '2026-09-28T21:45:21.515Z',
        'deleted': '2026-10-01T08:00:00.000Z',
        'touched': '2026-10-04T11:31:06.056Z',
        'acs': {'want': 'JRWPS', 'given': 'JRWPSD', 'mode': 'JRWPS'},
        'online': true,
        'seq': 9,
        'read': 7,
        'recv': 8,
        'clear': 2,
        'public': {
          'fn': 'Bob',
          'photo': {'type': 'png', 'ref': '/v0/file/s/x.png', 'width': 64},
          'org': {'fn': 'Acme'},
        },
        'private': {
          'comment': 'old friend',
          'arch': true,
          'accepted': 'JRWPS',
          'x-app-colour': 'red',
        },
        'seen': {'when': '2026-10-04T10:00:00.000Z', 'ua': 'probe/1'},
      }, 'sub');
      expect(Subscription.fromJson(viaText(chat.toJson()), 'sub'), chat);
    });

    test('a member with defaults only', () {
      final member = Subscription.fromJson(const {'user': 'usrA'}, 'sub');
      expect(member.toJson(), {'user': 'usrA'});
      expect(Subscription.fromJson(member.toJson(), 'sub'), member);
    });

    test('a search result', () {
      final found = FoundTopic.fromJson(const {
        'topic': 'grpX',
        'updated': '2026-10-08T15:01:42.041Z',
        'acs': {'mode': 'JRWPS'},
        'public': {'fn': 'Probe group'},
        'private': ['probegroup'],
        'subcnt': 2,
      }, 'sub');
      expect(FoundTopic.fromJson(viaText(found.toJson()), 'sub'), found);
      final bare = FoundTopic.fromJson(const {'user': 'usrB'}, 'sub');
      expect(bare.toJson(), {'topic': 'usrB'});
    });

    test('a group description', () {
      final desc = TopicDescription.fromJson(const {
        'created': '2026-09-01T00:00:00.000Z',
        'updated': '2026-09-02T00:00:00.000Z',
        'touched': '2026-10-04T11:31:06.056Z',
        'defacs': {'auth': 'JRWPS', 'anon': 'N'},
        'acs': {'want': 'JRWPASDO', 'given': 'JRWPASDO', 'mode': 'JRWPASDO'},
        'seq': 40,
        'read': 39,
        'recv': 40,
        'clear': 3,
        'public': {'fn': 'Coffee', 'note': 'beans'},
        'private': {
          'tpins': ['grpX', 'usrB'],
        },
      }, 'desc');
      expect(TopicDescription.fromJson(viaText(desc.toJson()), 'desc'), desc);
    });
  });

  group('built by hand', () {
    test('typed fields become wire keys', () {
      expect(
        const MessageHead(
          mime: MessageHead.draftyMime,
          callState: CallState.finished,
          callDuration: Duration(seconds: 3),
          audioOnly: true,
        ).toJson(),
        {
          'mime': 'text/x-drafty',
          'webrtc': 'finished',
          'webrtc-duration': 3000,
          'aonly': true,
        },
      );
      expect(
        PrivateSettings(
          comment: 'x',
          archived: true,
          accepted: AccessMode.parse('JRW'),
        ).toJson(),
        {'comment': 'x', 'arch': true, 'accepted': 'JRW'},
      );
      expect(
        const Profile(
          name: 'Bob',
          photo: ProfilePhoto(type: 'jpg', data: 'AAAA'),
        ).toJson(),
        {
          'fn': 'Bob',
          'photo': {'type': 'jpg', 'data': 'AAAA'},
        },
      );
    });

    test('raw wins over a typed field', () {
      expect(const Profile(name: 'typed', raw: {'fn': 'raw'}).toJson(), {
        'fn': 'raw',
      });
    });

    test('copyWith replaces typed fields and keeps the rest of raw', () {
      final read = Profile.fromJson(const {
        'fn': 'Old',
        'note': 'Hi',
        'org': {'fn': 'Acme'},
      });
      expect(
        read
            .copyWith(
              name: 'New',
              photo: const ProfilePhoto(type: 'jpg', ref: '/v0/file/s/a.jpg'),
            )
            .toJson(),
        {
          'fn': 'New',
          'note': 'Hi',
          'photo': {'type': 'jpg', 'ref': '/v0/file/s/a.jpg'},
          'org': {'fn': 'Acme'},
        },
      );
    });

    test('no access is written as N', () {
      expect(
        DefaultAccess(
          auth: AccessMode.parse('JRWPS'),
          anon: AccessMode.none,
        ).toJson(),
        {'auth': 'JRWPS', 'anon': 'N'},
      );
    });

    test('times are written in UTC', () {
      final message = DataMessage(
        topic: 'usrB',
        seq: 1,
        time: DateTime.utc(2026, 10, 4, 11, 31, 6, 56).toLocal(),
        content: const PlainText('hi'),
      );
      expect(message.toJson()['ts'], '2026-10-04T11:31:06.056Z');
    });

    test('a broken stored message is malformed', () {
      expect(
        () => DataMessage.fromJson(const {'topic': 'usrB', 'seq': 'x'}),
        throwsA(isA<MalformedPacketException>()),
      );
    });
  });
}
