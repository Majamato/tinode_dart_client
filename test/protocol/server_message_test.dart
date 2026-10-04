// Frames are based on captures from a Tinode v0.25.3 server (avatars trimmed),
// so they keep the wire layout rather than the lint rules.
// ignore_for_file: lines_longer_than_80_chars, missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

ServerMessage? parse(String frame) {
  final packet = jsonDecode(frame) as Json;
  final MapEntry(:key, :value) = packet.entries.single;
  return ServerMessage.fromPacket(key, value! as Json);
}

void main() {
  test('ctrl with params', () {
    final msg = parse(
      '{"ctrl":{"id":"10","topic":"usrS8SZdtb3xS0","params":{"seq":9},'
      '"code":202,"text":"accepted","ts":"2026-10-04T11:31:05.654Z"}}',
    );
    expect(
      msg,
      CtrlMessage(
        id: '10',
        topic: 'usrS8SZdtb3xS0',
        code: 202,
        text: 'accepted',
        params: const {'seq': 9},
        time: DateTime.utc(2026, 10, 4, 11, 31, 5, 654),
      ),
    );
    expect((msg! as CtrlMessage).isError, isFalse);
  });

  test('codes from 300 up are errors', () {
    bool isError(int code) =>
        (parse('{"ctrl":{"code":$code,"ts":"2026-10-04T11:31:05Z"}}')!
                as CtrlMessage)
            .isError;
    expect([200, 204, 208, 299].map(isError), everyElement(isFalse));
    expect([300, 401, 500].map(isError), everyElement(isTrue));
  });

  test('data with Drafty content', () {
    final msg = parse(
      '{"data":{"topic":"usrMMHQIDZI0e8","from":"usrMMHQIDZI0e8",'
      '"ts":"2026-10-04T11:31:06.056Z","seq":10,'
      '"head":{"mime":"text/x-drafty"},'
      '"content":{"fmt":[{"len":4,"tp":"ST"}],"txt":"bold"}}}',
    );
    expect(
      msg,
      DataMessage(
        topic: 'usrMMHQIDZI0e8',
        from: 'usrMMHQIDZI0e8',
        seq: 10,
        time: DateTime.utc(2026, 10, 4, 11, 31, 6, 56),
        head: MessageHead.fromJson(const {'mime': MessageHead.draftyMime}),
        content: const DraftyContent(
          Drafty(
            text: 'bold',
            spans: [Span(at: 0, length: 4, style: 'ST')],
          ),
        ),
      ),
    );
  });

  test('data from the server has no from or head', () {
    final msg = parse(
      '{"data":{"topic":"grpX","ts":"2026-10-04T11:31:06.056Z","seq":1,'
      '"content":"welcome"}}',
    );
    expect(
      msg,
      DataMessage(
        topic: 'grpX',
        seq: 1,
        time: DateTime.utc(2026, 10, 4, 11, 31, 6, 56),
        content: const PlainText('welcome'),
      ),
    );
  });

  test('meta with a P2P description', () {
    final msg = parse(
      '{"meta":{"id":"9","topic":"usrS8SZdtb3xS0","ts":"2026-10-04T11:31:05.253Z",'
      '"desc":{"created":"2026-09-28T12:57:21.454Z","touched":"2026-10-03T13:00:48.074Z",'
      '"seen":{"when":"2026-10-04T11:30:47.489Z","ua":"probe/1"},'
      '"acs":{"want":"JRWPA","given":"JRWPA","mode":"JRWPA"},'
      '"seq":8,"read":8,"recv":8,"public":{"fn":"Bob Smith",'
      '"photo":{"data":"/9j/","type":"jpg"}},"private":{"comment":""}}}}',
    );
    final meta = msg! as MetaMessage;
    expect(meta.id, '9');
    expect(meta.topic, 'usrS8SZdtb3xS0');
    final desc = meta.description!;
    expect(desc.created, DateTime.utc(2026, 9, 28, 12, 57, 21, 454));
    expect(desc.lastMessageAt, DateTime.utc(2026, 10, 3, 13, 0, 48, 74));
    expect(desc.lastSeq, 8);
    expect(desc.read, 8);
    expect(desc.received, 8);
    expect(desc.defaultAccess, isNull);
    expect(desc.public?.name, 'Bob Smith');
    expect(desc.private?.comment, isEmpty);
    expect(desc.seen?.userAgent, 'probe/1');
    expect(desc.access?.mode.has(Permission.approve), isTrue);
  });

  test('meta with a group description', () {
    final msg = parse(
      '{"meta":{"id":"5","topic":"grpX","ts":"2026-10-04T11:31:05.253Z",'
      '"desc":{"defacs":{"auth":"JRWPS","anon":"N"},"seq":3,"clear":2}}}',
    );
    final desc = (msg! as MetaMessage).description!;
    expect(
      desc.defaultAccess,
      DefaultAccess(auth: AccessMode.parse('JRWPS'), anon: AccessMode.none),
    );
    expect(desc.lastDeleteId, 2);
    expect(desc.seen, isNull);
  });

  test('meta with a chat list', () {
    final msg = parse(
      '{"meta":{"id":"4","topic":"me","ts":"2026-10-04T11:30:46.678Z","sub":['
      '{"updated":"2026-09-28T21:45:21.515Z","acs":{"want":"JRWPS",'
      '"given":"JRWPS","mode":"JRWPS"},"read":3,"recv":3,"seq":5,'
      '"public":{"fn":"Coffee Channel"},"topic":"grpaGzRk-6_6KA","online":true}]}}',
    );
    final chat = (msg! as MetaMessage).subscriptions.single;
    expect(chat.topic, 'grpaGzRk-6_6KA');
    expect(chat.unread, 2);
    expect(chat.online, isTrue);
  });

  test('pres and info', () {
    expect(
      parse(
        '{"pres":{"topic":"me","src":"usrS8SZdtb3xS0","what":"on","ua":"probe/1"}}',
      ),
      const PresMessage(
        topic: 'me',
        source: 'usrS8SZdtb3xS0',
        event: PresenceEvent.online,
        userAgent: 'probe/1',
      ),
    );
    expect(
      parse(
        '{"info":{"topic":"usrS8SZdtb3xS0","from":"usrS8SZdtb3xS0","what":"kp"}}',
      ),
      const InfoMessage(
        topic: 'usrS8SZdtb3xS0',
        from: 'usrS8SZdtb3xS0',
        event: InfoEvent.typing,
      ),
    );
  });

  test('every pres what maps to its event', () {
    const events = {
      'on': PresenceEvent.online,
      'off': PresenceEvent.offline,
      'ua': PresenceEvent.userAgent,
      'upd': PresenceEvent.updated,
      'tags': PresenceEvent.tags,
      'aux': PresenceEvent.aux,
      'acs': PresenceEvent.access,
      'gone': PresenceEvent.gone,
      'term': PresenceEvent.terminated,
      'msg': PresenceEvent.message,
      'read': PresenceEvent.read,
      'recv': PresenceEvent.received,
      'del': PresenceEvent.deleted,
      'teleport': PresenceEvent.unknown,
    };
    for (final MapEntry(key: what, value: event) in events.entries) {
      final pres = parse('{"pres":{"topic":"me","what":"$what"}}');
      expect((pres! as PresMessage).event, event, reason: what);
    }
    expect(
      parse('{"pres":{"topic":"me","src":"grpX","what":"msg","seq":4}}'),
      const PresMessage(
        topic: 'me',
        source: 'grpX',
        event: PresenceEvent.message,
        seq: 4,
      ),
    );
  });

  test('every info what maps to its event', () {
    const events = {
      'kp': InfoEvent.typing,
      'recv': InfoEvent.received,
      'read': InfoEvent.read,
      'call': InfoEvent.call,
      'teleport': InfoEvent.unknown,
    };
    for (final MapEntry(key: what, value: event) in events.entries) {
      final info = parse(
        '{"info":{"topic":"usrA","from":"usrA","what":"$what"}}',
      );
      expect((info! as InfoMessage).event, event, reason: what);
    }
    expect(
      parse('{"info":{"topic":"usrA","from":"usrA","what":"read","seq":7}}'),
      const InfoMessage(
        topic: 'usrA',
        from: 'usrA',
        event: InfoEvent.read,
        seq: 7,
      ),
    );
  });

  test('unknown packet types and enum values are tolerated', () {
    expect(parse('{"future":{"topic":"me"}}'), isNull);
    final pres = parse('{"pres":{"topic":"me","what":"teleport"}}');
    expect((pres! as PresMessage).event, PresenceEvent.unknown);
  });

  test('a broken envelope names the offending field', () {
    expect(
      () => parse(
        '{"data":{"topic":"me","seq":"1","ts":"2026-10-04T11:31:05Z"}}',
      ),
      throwsA(
        isA<MalformedPacketException>().having(
          (e) => e.path,
          'path',
          'data.seq',
        ),
      ),
    );
    expect(
      () => parse('{"ctrl":{"code":200,"ts":"yesterday"}}'),
      throwsA(
        isA<MalformedPacketException>().having(
          (e) => e.path,
          'path',
          'ctrl.ts',
        ),
      ),
    );
  });
}
