@Tags(['integration', 'smtp'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import 'account_test.dart' show connect, uniqueLogin;
import 'mailpit.dart';

// Needs the server to require an email at sign-up and send it to Mailpit
// (see mailpit.dart):
//   dart test -P smtp

Matcher throwsCode(int code) =>
    throwsA(isA<ServerException>().having((e) => e.code, 'code', code));

final Matcher throwsCredentialsRequired = throwsA(
  isA<CredentialsRequiredException>().having((e) => e.methods, 'methods', [
    'email',
  ]),
);

void main() {
  setUp(clearMail);

  test('an account confirms its email with the mailed code', () async {
    final client = await connect();
    expect(client.serverInfo.requiredCredentials, ['email']);
    final login = uniqueLogin('pe');
    final email = '$login@example.com';

    await expectLater(
      client.createAccount(login: login, password: 'secret1'),
      throwsCode(422),
    );
    await expectLater(
      client.createAccount(login: login, password: 'secret1', email: email),
      throwsCredentialsRequired,
    );
    final code = await mailedCode(email);

    // Not logged in until it is confirmed: no login works without it.
    final other = await connect();
    await expectLater(
      other.loginBasic(login, 'secret1'),
      throwsCredentialsRequired,
    );
    await expectLater(
      other.loginBasic(login, 'secret1', codes: const {'email': '000000'}),
      throwsCredentialsRequired,
    );

    final result = await client.loginBasic(
      login,
      'secret1',
      codes: {'email': code},
    );
    expect(client.userId, result.userId);
    await client.subscribe('me');
    expect((await other.loginBasic(login, 'secret1')).userId, result.userId);

    // The email is taken now, and reaches the user as a tag.
    final third = await connect();
    await expectLater(
      third.createAccount(
        login: uniqueLogin('pf'),
        password: 'secret1',
        email: email,
      ),
      throwsA(
        isA<ServerException>()
            .having((e) => e.code, 'code', 409)
            .having((e) => e.params['what'], 'what', isNot('auth')),
      ),
    );
    final alice = await connect();
    await alice.loginBasic('alice', 'alice123');
    expect((await alice.find(email)).single.topic, result.userId);

    await client.deleteAccount();
  });

  test('an email that is not one is 400', () async {
    final client = await connect();
    await expectLater(
      client.createAccount(
        login: uniqueLogin('pg'),
        password: 'secret1',
        email: 'not-an-email',
      ),
      throwsCode(400),
    );
  });
}
