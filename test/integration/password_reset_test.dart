@Tags(['integration', 'smtp'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import 'account_test.dart' show config;
import 'mailpit.dart';

// Needs the server to send its email to Mailpit (see mailpit.dart):
//   dart test -P smtp
// That setup requires an email at sign-up, so run the other integration
// suites without it. It resets alice's password to the one she
// already has, so other suites keep logging in. A run that fails between
// the request and the reset leaves a code pending for 15 minutes, which
// makes the next request a 409 until then.
void main() {
  const email = 'alice@example.com';

  setUp(clearMail);

  test('a reset code sets a new password', () async {
    final client = await TinodeClient.connect(config);
    addTearDown(client.close);

    await client.requestPasswordReset(email);
    final code = await mailedCode(email);
    expect(code, hasLength(6));
    // No second code while the first is valid.
    await expectLater(
      client.requestPasswordReset(email),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 409)),
    );
    await client.resetPassword(email: email, code: code, password: 'alice123');

    expect((await client.loginBasic('alice', 'alice123')).userId, isNotEmpty);
  });
}
