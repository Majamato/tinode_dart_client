import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

void main() {
  group('MessageHead', () {
    test('reads the call that a message starts', () {
      final head = MessageHead.fromJson({
        'webrtc': 'started',
        'aonly': true,
        'mime': 'text/x-drafty',
      });
      expect(head.callState, CallState.started);
      expect(head.audioOnly, isTrue);
      expect(head.callDuration, isNull);
    });

    test("reads the server's update to a finished call", () {
      final head = MessageHead.fromJson({
        'replace': ':12',
        'webrtc': 'finished',
        'webrtc-duration': 61234,
      });
      expect(head.callState, CallState.finished);
      expect(head.callDuration, const Duration(milliseconds: 61234));
      expect(head.replacesSeq, 12);
      expect(head.audioOnly, isFalse);
    });

    test('a call state from a newer server is unknown', () {
      expect(
        MessageHead.fromJson({'webrtc': 'on-hold'}).callState,
        CallState.unknown,
      );
    });

    test('ordinary messages have no call', () {
      final head = MessageHead.fromJson({'mime': 'text/x-drafty'});
      expect(head.callState, isNull);
      expect(head.callDuration, isNull);
      expect(head.audioOnly, isFalse);
      expect(head.replacesSeq, isNull);
    });

    test('wrongly typed call fields are ignored', () {
      final head = MessageHead.fromJson({
        'webrtc': 3,
        'webrtc-duration': '61',
        'aonly': 'yes',
      });
      expect(head.callState, isNull);
      expect(head.callDuration, isNull);
      expect(head.audioOnly, isFalse);
    });

    test('a malformed replace has no seq', () {
      for (final replace in ['12', ':', ':x', 'usrBob:12']) {
        expect(
          MessageHead.fromJson({'replace': replace}).replacesSeq,
          isNull,
          reason: replace,
        );
      }
    });
  });

  group('CallState', () {
    test('is over once the call can no longer be joined', () {
      expect(
        CallState.values.where((s) => s.isOver),
        unorderedEquals([
          CallState.finished,
          CallState.missed,
          CallState.declined,
          CallState.disconnected,
          CallState.busy,
        ]),
      );
    });
  });
}
