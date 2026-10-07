import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

void main() {
  group('ServerInfo', () {
    test('reads the ICE servers and call timeout', () {
      final info = ServerInfo.fromParams({
        'ver': '0.25',
        'iceServers': [
          {
            'urls': ['stun:stun.example.com:80'],
          },
          {
            'username': 'u',
            'credential': 'p',
            'urls': [
              'turn:turn.example.com:80',
              'turns:turn.example.com:443?transport=tcp',
            ],
          },
        ],
        'callTimeout': 30,
      });
      expect(info.iceServers, const [
        IceServer(urls: ['stun:stun.example.com:80']),
        IceServer(
          urls: [
            'turn:turn.example.com:80',
            'turns:turn.example.com:443?transport=tcp',
          ],
          username: 'u',
          credential: 'p',
        ),
      ]);
      expect(info.callTimeout, const Duration(seconds: 30));
      expect(info.callsEnabled, isTrue);
    });

    test('accepts a single url and the credential type', () {
      final info = ServerInfo.fromParams({
        'iceServers': [
          {'urls': 'turn:turn.example.com', 'credential_type': 'password'},
        ],
      });
      expect(
        info.iceServers.single,
        const IceServer(
          urls: ['turn:turn.example.com'],
          credentialType: 'password',
        ),
      );
    });

    test('drops servers it cannot use', () {
      final info = ServerInfo.fromParams({
        'iceServers': [
          'stun:stun.example.com',
          {'username': 'u'},
          {'urls': <Object?>[]},
          {
            'urls': [3, 'stun:ok.example.com'],
          },
        ],
      });
      expect(info.iceServers, const [
        IceServer(urls: ['stun:ok.example.com']),
      ]);
    });

    test('without ICE servers calls are off', () {
      final info = ServerInfo.fromParams({'ver': '0.25'});
      expect(info.iceServers, isEmpty);
      expect(info.callTimeout, isNull);
      expect(info.callsEnabled, isFalse);
    });
  });
}
