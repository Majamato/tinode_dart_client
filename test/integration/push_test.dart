@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import 'account_test.dart' show signUp, uniqueLogin;

// The server stores device tokens whether or not it has push configured,
// so this checks it takes every step, not that a push arrives.
void main() {
  test('a token is registered, replaced and removed', () async {
    final (client, _) = await signUp('push');
    await client.setDeviceToken('fcm-${uniqueLogin('a')}');
    await client.setDeviceToken('fcm-${uniqueLogin('b')}');
    await client.setDeviceToken(null);
  });

  test('a token set before sign-up is registered with it', () async {
    final client = await TinodeClient.connect(
      TinodeConfig(
        server: Uri.parse('ws://localhost:6060'),
        apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
        userAgent: 'tinode_dart_client-test/0.1',
        platform: DevicePlatform.android,
      ),
    );
    addTearDown(client.close);
    await client.setDeviceToken('fcm-${uniqueLogin('c')}');
    final login = uniqueLogin('push');
    await client.createAccount(login: login, password: 'secret1');
    addTearDown(client.deleteAccount);
    expect(client.status, isA<Connected>());
    await client.setDeviceToken(null);
  });
}
