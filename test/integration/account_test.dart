@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

// Runs against a Tinode server. Each test signs up its own users under a
// unique login and deletes them at the end, so runs leave nothing behind.
final config = TinodeConfig(
  server: Uri.parse('ws://localhost:6060'),
  apiKey: 'AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K',
  userAgent: 'tinode_dart_client-test/0.1',
);

Future<TinodeClient> connect() async {
  final client = await TinodeClient.connect(config);
  addTearDown(client.close);
  return client;
}

/// A login no earlier run used; logins are 3 to 32 lowercase characters.
String uniqueLogin(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch % 10000000000}';

/// Signs up a new user, deleted again when the test ends.
Future<(TinodeClient, LoginResult)> signUp(String prefix) async {
  final client = await connect();
  final login = uniqueLogin(prefix);
  final result = await client.createAccount(
    login: login,
    password: 'secret1',
    public: Profile(name: 'Probe $login'),
  );
  addTearDown(() async {
    if (client.status is Connected) await client.deleteAccount();
  });
  return (client, result);
}

Matcher throwsCode(int code) =>
    throwsA(isA<ServerException>().having((e) => e.code, 'code', code));

void main() {
  test('a new account is logged in, findable and has its profile', () async {
    final (user, result) = await signUp('pa');
    expect(user.userId, result.userId);
    expect(result.token, isNotEmpty);

    final desc = await user.getDescription('me');
    expect(desc?.public?.name, startsWith('Probe pa'));

    final (other, _) = await signUp('pb');
    final login = desc!.public!.name!.substring('Probe '.length);
    final found = await other.find('basic:$login');
    expect(found.single.topic, result.userId);
  });

  test('a taken login is 409, a too short password 422', () async {
    final (user, _) = await signUp('pb');
    final login = (await user.getDescription(
      'me',
    ))!.public!.name!.substring('Probe '.length);
    final client = await connect();
    await expectLater(
      client.createAccount(login: login, password: 'secret1'),
      throwsCode(409),
    );
    await expectLater(
      client.createAccount(login: uniqueLogin('pc'), password: 'ab'),
      throwsCode(422),
    );
  });

  test('a changed password and login log in; the old ones do not', () async {
    final (user, result) = await signUp('pa');
    await user.changePassword('secret2');
    final renamed = uniqueLogin('pr');
    await user.changePassword('secret3', login: renamed);

    final again = await connect();
    expect((await again.loginBasic(renamed, 'secret3')).userId, result.userId);
    final old = await connect();
    await expectLater(old.loginBasic(renamed, 'secret2'), throwsCode(401));

    final (other, _) = await signUp('pb');
    expect((await other.find('basic:$renamed')).single.topic, result.userId);
  });

  test('renaming to a taken login is 409', () async {
    final (user, _) = await signUp('pa');
    await expectLater(
      user.changePassword('secret1', login: 'alice'),
      throwsCode(409),
    );
  });

  test('a deleted account closes the client and cannot log in', () async {
    final client = await connect();
    final login = uniqueLogin('pd');
    await client.createAccount(login: login, password: 'secret1');
    await client.deleteAccount();
    expect(client.status, const Disconnected());

    final again = await connect();
    await expectLater(again.loginBasic(login, 'secret1'), throwsCode(401));
  });

  test('a reset request is taken without knowing the email', () async {
    final client = await connect();
    await client.requestPasswordReset('${uniqueLogin('nobody')}@example.com');
    await expectLater(
      client.resetPassword(
        email: 'nobody@example.com',
        code: '000000',
        password: 'secret1',
      ),
      throwsCode(401),
    );
  });
}
