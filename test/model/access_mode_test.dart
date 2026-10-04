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

    test('N and unknown letters mean no permission', () {
      expect(AccessMode.parse('N'), AccessMode.none);
      expect(AccessMode.parse('XZ'), AccessMode.none);
      expect(AccessMode.none.toString(), 'N');
    });

    test('intersect keeps only shared permissions', () {
      final want = AccessMode.parse('JRWPA');
      final given = AccessMode.parse('JRP');
      expect(want.intersect(given), AccessMode.parse('JRP'));
    });

    test('Access reads want, given and mode', () {
      final acs = Access.fromJson({'want': 'JRWPA', 'given': 'JRWP'}, 'acs');
      expect(acs.want.has(Permission.approve), isTrue);
      expect(acs.given.has(Permission.approve), isFalse);
      expect(acs.mode, AccessMode.none);
    });
  });
}
