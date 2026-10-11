import 'dart:convert';

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

void main() {
  group('tryParse', () {
    test('a message, as FCM delivers it', () {
      final data = {
        'what': 'msg',
        'topic': 'usrBob',
        'xfrom': 'usrBob',
        'ts': '2026-10-11T08:30:00.123Z',
        'seq': '42',
        'mime': 'text/x-drafty',
        'content': 'Hello there',
        'rc': jsonEncode({
          'txt': 'Hello there',
          'fmt': [
            {'at': 0, 'len': 5, 'tp': 'ST'},
          ],
        }),
        'replace': ':40',
      };
      final push = TinodePush.tryParse(data)! as MessagePush;
      expect(push.topic, 'usrBob');
      expect(push.from, 'usrBob');
      expect(push.sentAt, DateTime.utc(2026, 10, 11, 8, 30, 0, 123));
      expect(push.silent, isFalse);
      expect(push.seq, 42);
      expect(push.mimeType, 'text/x-drafty');
      expect(push.text, 'Hello there');
      expect(push.preview?.text, 'Hello there');
      expect(push.preview?.spans, hasLength(1));
      expect(push.callState, isNull);
      expect(push.replaces, ':40');
      expect(push.raw, data);
      expect(TinodePush.tryParse(push.toJson()), push);
    });

    test('a call', () {
      final push =
          TinodePush.tryParse({
                'what': 'msg',
                'topic': 'usrBob',
                'seq': '7',
                'webrtc': 'started',
                'aonly': 'true',
                'silent': 'true',
              })!
              as MessagePush;
      expect(push.callState, CallState.started);
      expect(push.audioOnly, isTrue);
      expect(push.silent, isTrue);
    });

    test('a new subscription', () {
      final push =
          TinodePush.tryParse({
                'what': 'sub',
                'topic': 'grpHikers',
                'xfrom': 'usrBob',
                'modeWant': 'JRWPS',
                'modeGiven': 'JRWP',
              })!
              as SubscriptionPush;
      expect(push.topic, 'grpHikers');
      expect(push.want, AccessMode.parse('JRWPS'));
      expect(push.given, AccessMode.parse('JRWP'));
    });

    test('a read elsewhere', () {
      final push =
          TinodePush.tryParse({
                'what': 'read',
                'topic': 'grpHikers',
                'seq': '12',
                'silent': 'true',
              })!
              as ReadPush;
      expect(push.seq, 12);
      expect(push.silent, isTrue);
    });

    test('typed values are read too', () {
      final push =
          TinodePush.tryParse({
                'what': 'msg',
                'topic': 'usrBob',
                'seq': 3,
                'silent': true,
              })!
              as MessagePush;
      expect(push.seq, 3);
      expect(push.silent, isTrue);
    });

    test('malformed fields read as missing', () {
      final push =
          TinodePush.tryParse({
                'what': 'msg',
                'topic': 'usrBob',
                'seq': 'x',
                'ts': 'yesterday',
                'rc': '{not json',
              })!
              as MessagePush;
      expect(push.seq, isNull);
      expect(push.sentAt, isNull);
      expect(push.preview, isNull);
    });

    test('anything else is null', () {
      expect(TinodePush.tryParse({}), isNull);
      expect(TinodePush.tryParse({'what': 'msg'}), isNull);
      expect(TinodePush.tryParse({'what': 'msg', 'topic': ''}), isNull);
      expect(TinodePush.tryParse({'what': 'poke', 'topic': 'usrB'}), isNull);
      expect(TinodePush.tryParse({'title': 'Sale!', 'body': '50%'}), isNull);
    });
  });
}
