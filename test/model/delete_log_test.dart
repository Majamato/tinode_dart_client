import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

void main() {
  group('SeqRange', () {
    test('a missing hi means a single seq', () {
      final range = SeqRange.fromJson(const {'low': 4}, 'r');
      expect(range, const SeqRange.single(4));
      expect(range.length, 1);
      expect(range.contains(4), isTrue);
      expect(range.contains(5), isFalse);
    });

    test('hi is exclusive', () {
      final range = SeqRange.fromJson(const {'low': 4, 'hi': 7}, 'r');
      expect([3, 4, 6, 7].map(range.contains), [false, true, true, false]);
      expect(range.length, 3);
    });

    test('a hi at or below low is a single seq', () {
      expect(
        SeqRange.fromJson(const {'low': 4, 'hi': 0}, 'r'),
        const SeqRange.single(4),
      );
      expect(
        SeqRange.fromJson(const {'low': 4, 'hi': 4}, 'r'),
        const SeqRange.single(4),
      );
    });

    test('a missing or non-positive low is malformed', () {
      expect(
        () => SeqRange.fromJson(const {'hi': 4}, 'r'),
        throwsA(isA<MalformedPacketException>()),
      );
      expect(
        () => SeqRange.fromJson(const {'low': 0}, 'r'),
        throwsA(isA<MalformedPacketException>()),
      );
    });

    test('toJson leaves out hi for a single seq', () {
      expect(const SeqRange.single(4).toJson(), {'low': 4});
      expect(const SeqRange(4, 6).toJson(), {'low': 4, 'hi': 6});
    });
  });

  group('DeleteLog', () {
    test('parses clear and delseq', () {
      expect(
        DeleteLog.fromJson(const {
          'clear': 2,
          'delseq': [
            {'low': 1, 'hi': 3},
          ],
        }, 'meta.del'),
        const DeleteLog(lastDeleteId: 2, ranges: [SeqRange(1, 3)]),
      );
    });

    test('a broken range names its path', () {
      expect(
        () => DeleteLog.fromJson(const {
          'delseq': [
            {'low': 'x'},
          ],
        }, 'meta.del'),
        throwsA(
          isA<MalformedPacketException>().having(
            (e) => e.toString(),
            'message',
            contains('meta.del.delseq[0].low'),
          ),
        ),
      );
    });
  });
}
