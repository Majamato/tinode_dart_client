import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

void main() {
  group('AccessMode', () {
    test('parses letters and prints them back in canonical order', () {
      final mode = AccessMode.parse('SPWRJ');
      expect(mode.permissions, {
        Permission.join,
        Permission.read,
        Permission.write,
        Permission.presence,
        Permission.share,
      });
      expect(mode.toString(), 'JRWPS');
    });

    test('every letter maps to its permission', () {
      const letters = {
        'J': Permission.join,
        'R': Permission.read,
        'W': Permission.write,
        'P': Permission.presence,
        'A': Permission.approve,
        'S': Permission.share,
        'D': Permission.delete,
        'O': Permission.owner,
      };
      for (final MapEntry(key: letter, value: permission) in letters.entries) {
        expect(AccessMode.parse(letter).permissions, {permission});
      }
      expect(AccessMode.parse('JRWPASDO').toString(), 'JRWPASDO');
      expect(AccessMode(Permission.values), AccessMode.parse('ODSAPWRJ'));
    });

    test('N is none, and prints back as N', () {
      expect(AccessMode.parse('N'), AccessMode.none);
      expect(AccessMode.parse(''), AccessMode.none);
      expect(AccessMode.none.toString(), 'N');
      expect(AccessMode.none.permissions, isEmpty);
    });

    test('unknown letters are ignored, N included', () {
      expect(AccessMode.parse('XZ'), AccessMode.none);
      expect(AccessMode.parse('JXRN'), AccessMode.parse('JR'));
    });

    test('repeated letters count once', () {
      expect(AccessMode.parse('JJRR').toString(), 'JR');
    });

    test('intersect keeps only shared permissions', () {
      final want = AccessMode.parse('JRWPA');
      final given = AccessMode.parse('JRPS');
      expect(want.intersect(given), AccessMode.parse('JRP'));
      expect(given.intersect(want), AccessMode.parse('JRP'));
      expect(want.intersect(AccessMode.parse('SDO')), AccessMode.none);
      expect(want.intersect(AccessMode.none), AccessMode.none);
    });
  });

  group('Access', () {
    test('reads want, given and mode', () {
      final acs = Access.fromJson({
        'want': 'JRWPA',
        'given': 'JRWP',
        'mode': 'JRWP',
      }, 'acs');
      expect(
        acs,
        Access(
          want: AccessMode.parse('JRWPA'),
          given: AccessMode.parse('JRWP'),
          mode: AccessMode.parse('JRWP'),
        ),
      );
    });

    test('a missing field is none', () {
      expect(
        Access.fromJson({}, 'acs'),
        const Access(
          want: AccessMode.none,
          given: AccessMode.none,
          mode: AccessMode.none,
        ),
      );
    });

    test('a non-string field is malformed', () {
      expect(
        () => Access.fromJson({'want': 'JR', 'given': 7}, 'meta.desc.acs'),
        throwsA(
          isA<MalformedPacketException>().having(
            (e) => e.path,
            'path',
            'meta.desc.acs.given',
          ),
        ),
      );
    });
  });

  group('DefaultAccess', () {
    test('reads auth and anon', () {
      expect(
        DefaultAccess.fromJson({'auth': 'JRWPS', 'anon': 'N'}, 'defacs'),
        DefaultAccess(auth: AccessMode.parse('JRWPS'), anon: AccessMode.none),
      );
    });

    test('a missing field is none', () {
      expect(
        DefaultAccess.fromJson({'auth': 'JR'}, 'defacs'),
        DefaultAccess(auth: AccessMode.parse('JR'), anon: AccessMode.none),
      );
    });

    test('a non-string field is malformed', () {
      expect(
        () => DefaultAccess.fromJson({'anon': true}, 'meta.desc.defacs'),
        throwsA(
          isA<MalformedPacketException>().having(
            (e) => e.path,
            'path',
            'meta.desc.defacs.anon',
          ),
        ),
      );
    });
  });
}
