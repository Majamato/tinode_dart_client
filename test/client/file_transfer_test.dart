import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

import '../support/fake_server.dart';

final config = TinodeConfig(
  server: Uri.parse('wss://chat.example.com/tinode'),
  apiKey: 'key',
  userAgent: 'test/1.0',
);

typedef Handler =
    Future<http.StreamedResponse> Function(
      http.BaseRequest request,
      List<int> body,
    );

http.StreamedResponse reply(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body is String ? body : jsonEncode(body))),
  status,
  headers: headers,
);

/// When the server answered the uploads, a minute before they expire.
const replyTime = '2026-10-09T01:56:02.227Z';

Json ctrl(int code, {String text = 'ok', Json? params}) => {
  'ctrl': {'code': code, 'text': text, 'params': ?params, 'ts': replyTime},
};

const uploaded = {
  'url': '/v0/file/s/abc.txt',
  'expires': '2026-10-09T01:57:02.227',
};

Stream<List<int>> Function() source(List<List<int>> chunks) =>
    () => Stream.fromIterable(chunks);

void main() {
  late FakeServer server;
  late TinodeClient client;
  late List<http.BaseRequest> requests;
  late Handler handler;

  setUp(() async {
    requests = [];
    handler = (_, _) async => reply(200, ctrl(200, params: uploaded));
    server = FakeServer();
    final connecting = TinodeClient.connect(
      config,
      connector: (_) async => server.client,
      httpClient: MockClient.streaming((request, body) async {
        requests.add(request);
        return handler(request, await body.toBytes());
      }),
    );
    await server.handshake();
    client = await connecting;
  });

  tearDown(() => client.close());

  Future<void> logIn() async {
    final login = client.loginToken('old');
    server.ctrl(
      await server.next('login'),
      params: {'user': 'usrA', 'token': 'tok'},
    );
    await login;
  }

  Future<UploadResult> upload({
    Stream<List<int>> Function()? openRead,
    void Function(int, int)? onProgress,
    Future<void>? abortTrigger,
  }) => client.upload(
    openRead ?? source([utf8.encode('hello')]),
    length: 5,
    filename: 'a.txt',
    mimeType: 'text/plain',
    onProgress: onProgress,
    abortTrigger: abortTrigger,
  );

  group('upload', () {
    test('posts the file as multipart, logged in by header', () async {
      await logIn();
      late String body;
      handler = (request, bytes) async {
        body = utf8.decode(bytes);
        return reply(200, ctrl(200, params: uploaded));
      };

      final before = DateTime.now().toUtc();
      final result = await upload();

      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://chat.example.com/tinode/v0/file/u/',
      );
      expect(request.headers, containsPair('X-Tinode-APIKey', 'key'));
      expect(request.headers, containsPair('X-Tinode-Auth', 'Token tok'));
      expect(request.url.query, isEmpty);
      expect(body, contains('name="file"; filename="a.txt"'));
      expect(body, contains('content-type: text/plain'));
      expect(body, contains('hello'));
      expect(result.ref, '/v0/file/s/abc.txt');
      // The server's minute (its expiry has no zone: it is UTC), counted
      // on this device's clock.
      expect(
        result.expires!.difference(before).inSeconds,
        inInclusiveRange(59, 60),
      );
    });

    test('reports the bytes sent so far', () async {
      await logIn();
      final progress = <(int, int)>[];
      await upload(
        openRead: source([
          [1, 2],
          [3, 4, 5],
        ]),
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(progress, [(2, 5), (5, 5)]);
    });

    test('needs a login', () async {
      expect(upload, throwsStateError);
      expect(requests, isEmpty);
    });

    test('a refusal throws the ctrl code and text', () async {
      await logIn();
      handler = (_, _) async =>
          reply(413, ctrl(413, text: 'request too large'));
      await expectLater(
        upload(),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'code', 413)
              .having((e) => e.text, 'text', 'request too large'),
        ),
      );

      handler = (_, _) async => reply(401, {
        'ctrl': {'code': 401, 'text': 'authentication required'},
      });
      await expectLater(
        upload(),
        throwsA(isA<ServerException>().having((e) => e.code, 'code', 401)),
      );
    });

    test('a reply that is no ctrl throws the HTTP status', () async {
      await logIn();
      handler = (_, _) async => reply(502, '<html>Bad gateway</html>');
      await expectLater(
        upload(),
        throwsA(isA<ServerException>().having((e) => e.code, 'code', 502)),
      );
    });

    test('a network failure throws ServerUnreachableException', () async {
      await logIn();
      handler = (request, _) async =>
          throw http.ClientException('Connection reset', request.url);
      await expectLater(upload(), throwsA(isA<ServerUnreachableException>()));
    });

    test('a 307 sends the file again, read from the start', () async {
      await logIn();
      final bodies = <String>[];
      handler = (request, bytes) async {
        bodies.add(utf8.decode(bytes));
        return bodies.length == 1
            ? reply(307, '', headers: {'location': '/tinode/v0/file/u/2'})
            : reply(200, ctrl(200, params: uploaded));
      };
      var opened = 0;
      final result = await upload(
        openRead: () {
          opened++;
          return Stream.value(utf8.encode('hello'));
        },
      );
      expect(result.ref, '/v0/file/s/abc.txt');
      expect(opened, 2);
      expect(bodies, everyElement(contains('hello')));
      expect(
        requests.last.url.toString(),
        'https://chat.example.com/tinode/v0/file/u/2',
      );
      expect(requests.last.headers, containsPair('X-Tinode-Auth', 'Token tok'));
    });

    test('an abort ends it with TransferAbortedException', () async {
      await logIn();
      final hold = Completer<void>();
      addTearDown(hold.complete);
      handler = (_, _) async {
        await hold.future;
        return reply(200, ctrl(200, params: uploaded));
      };
      final abort = Completer<void>();
      final result = upload(abortTrigger: abort.future);
      await Future<void>.delayed(Duration.zero);
      abort.complete();
      await expectLater(result, throwsA(isA<TransferAbortedException>()));
    });

    test('an abort before it starts sends nothing', () async {
      await logIn();
      await expectLater(
        upload(abortTrigger: Future.value()),
        throwsA(isA<TransferAbortedException>()),
      );
    });
  });

  group('download', () {
    test('fetches a relative ref from the server, logged in', () async {
      await logIn();
      handler = (_, _) async => reply(
        200,
        'hello',
        headers: {'content-type': 'text/plain', 'etag': '"e1"'},
      );

      final download = await client.download('/v0/file/s/abc.txt');

      expect(
        utf8.decode(await http.ByteStream(download.bytes).toBytes()),
        'hello',
      );
      expect(download.mimeType, 'text/plain');
      expect(download.etag, '"e1"');
      final request = requests.single;
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://chat.example.com/tinode/v0/file/s/abc.txt',
      );
      expect(request.headers, containsPair('X-Tinode-Auth', 'Token tok'));
      expect(request.followRedirects, isFalse);
    });

    test('drops the login on a redirect to another origin', () async {
      await logIn();
      handler = (request, _) async => request.url.host == 'chat.example.com'
          ? reply(
              302,
              '',
              headers: {'location': 'https://bucket.s3.example/abc?sig=1'},
            )
          : reply(200, 'hello');

      final download = await client.download('/v0/file/s/abc.txt');
      await download.bytes.drain<void>();

      expect(requests, hasLength(2));
      expect(requests.first.headers, contains('X-Tinode-Auth'));
      expect(requests.last.url.host, 'bucket.s3.example');
      expect(requests.last.headers, isNot(contains('X-Tinode-Auth')));
      expect(requests.last.headers, isNot(contains('X-Tinode-APIKey')));
    });

    test('fetches a foreign absolute ref without credentials', () async {
      handler = (_, _) async => reply(200, 'x');
      final download = await client.download('https://cdn.example/a.png');
      await download.bytes.drain<void>();
      expect(requests.single.headers, isNot(contains('X-Tinode-Auth')));
    });

    test('gives up after too many redirects', () async {
      await logIn();
      handler = (_, _) async =>
          reply(302, '', headers: {'location': '/tinode/v0/file/s/again'});
      await expectLater(
        client.download('/v0/file/s/abc.txt'),
        throwsA(isA<ServerException>()),
      );
      expect(requests, hasLength(6));
    });

    test('a failure throws the ctrl code', () async {
      await logIn();
      handler = (_, _) async => reply(404, ctrl(404, text: 'not found'));
      await expectLater(
        client.download('/v0/file/s/gone.txt'),
        throwsA(isA<ServerException>().having((e) => e.code, 'code', 404)),
      );
    });

    test('refuses refs that are not http(s)', () async {
      await logIn();
      expect(() => client.download('javascript:alert(1)'), throwsArgumentError);
    });

    test('an abort while streaming ends the bytes', () async {
      await logIn();
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      handler = (_, _) async => http.StreamedResponse(body.stream, 200);
      final abort = Completer<void>();
      final download = await client.download(
        '/v0/file/s/abc.txt',
        abortTrigger: abort.future,
      );
      final received = download.bytes.toList();
      body.add([1]);
      await Future<void>.delayed(Duration.zero);
      abort.complete();
      await expectLater(received, throwsA(isA<TransferAbortedException>()));
    });
  });
}
