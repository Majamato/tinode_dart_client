import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tinode_dart_client/src/client/results.dart';
import 'package:tinode_dart_client/src/client/tinode_config.dart';
import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';

/// How many redirects a download follows.
const maxRedirects = 5;

/// Uploads and downloads over HTTP, logged in with the session's latest
/// token. Credentials go only to the server's own origin, as headers.
final class FileTransfer {
  FileTransfer(this._config, this._token, {http.Client? client})
    : _client = client,
      _ownsClient = client == null;

  final TinodeConfig _config;
  final String? Function() _token;
  final bool _ownsClient;
  http.Client? _client;

  http.Client get _http => _client ??= http.Client();

  Future<UploadResult> upload(
    Stream<List<int>> Function() openRead, {
    required int length,
    required String filename,
    String? mimeType,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final token = _requireToken();
    final abort = _Abort(abortTrigger);
    var url = _config.uploadUri;
    for (var attempt = 1; ; attempt++) {
      var sent = 0;
      final body = openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, length);
        return chunk;
      });
      final request =
          http.AbortableMultipartRequest(
              'POST',
              url,
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers.addAll(_credentials(url, token))
            ..files.add(
              http.MultipartFile(
                'file',
                abort.guard(body, url),
                length,
                filename: filename,
                contentType: _mediaType(mimeType),
              ),
            );
      final response = await _send(request, abort);
      // The server asks to send it elsewhere: once, from the start.
      if (response.statusCode == 307 && attempt == 1) {
        if (response.headers['location'] case final location?) {
          await _discard(response);
          url = url.resolve(location);
          continue;
        }
      }
      final reply = await _readBody(response, abort);
      final ctrl = _ctrlOf(reply);
      if (ctrl == null) {
        throw ServerException(response.statusCode, 'not a ctrl reply');
      }
      final code = LooseJson(ctrl).get<int>('code') ?? response.statusCode;
      if (code >= 300 || response.statusCode >= 300) {
        throw _rejection(ctrl, code >= 300 ? code : response.statusCode);
      }
      final params = LooseJson(ctrl).get<Json>('params') ?? const {};
      return UploadResult(
        ref: StrictJson(params).require('url', 'ctrl.params'),
        expires: _localExpiry(
          _serverTime(LooseJson(params).get('expires')),
          LooseJson(ctrl).time('ts'),
        ),
      );
    }
  }

  Future<FileDownload> download(
    String ref, {
    Future<void>? abortTrigger,
  }) async {
    var url = _config.resolveFile(ref);
    final abort = _Abort(abortTrigger);
    for (var hop = 0; ; hop++) {
      final token = _config.isOwnOrigin(url) ? _requireToken() : null;
      final request =
          http.AbortableRequest('GET', url, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers.addAll(
              token == null ? const {} : _credentials(url, token),
            );
      final response = await _send(request, abort);
      final status = response.statusCode;
      if (_redirects.contains(status)) {
        if (response.headers['location'] case final location?) {
          await _discard(response);
          if (hop >= maxRedirects) {
            throw ServerException(status, 'too many redirects');
          }
          url = url.resolve(location);
          if (!url.isScheme('http') && !url.isScheme('https')) {
            throw ServerException(status, 'redirect to $url');
          }
          continue;
        }
      }
      if (status < 200 || status >= 300) {
        final ctrl = _ctrlOf(await _readBody(response, abort));
        final code = switch (ctrl) {
          null => status,
          final ctrl => LooseJson(ctrl).get<int>('code') ?? status,
        };
        throw ctrl == null
            ? ServerException(status, response.reasonPhrase ?? '')
            : _rejection(ctrl, code);
      }
      return FileDownload(
        bytes: abort.guard(
          response.stream.handleError(
            (Object e) => throw ServerUnreachableException(e),
            test: (e) => e is http.ClientException && !abort.aborted,
          ),
          url,
        ),
        length: response.contentLength,
        mimeType: response.headers['content-type'],
        etag: response.headers['etag'],
      );
    }
  }

  void close() {
    if (_ownsClient) _client?.close();
  }

  static const _redirects = {301, 302, 303, 307, 308};

  String _requireToken() =>
      _token() ?? (throw StateError('Log in before transferring files.'));

  /// The API key and the login, for the server's own origin only.
  Map<String, String> _credentials(Uri url, String token) =>
      _config.isOwnOrigin(url)
      ? {'X-Tinode-APIKey': _config.apiKey, 'X-Tinode-Auth': 'Token $token'}
      : const {};

  /// Sends [request]; network failures become [ServerUnreachableException].
  Future<http.StreamedResponse> _send(
    http.BaseRequest request,
    _Abort abort,
  ) async {
    if (abort.aborted) throw TransferAbortedException(request.url);
    try {
      return await abort.race(_http.send(request), request.url);
    } on TransferAbortedException {
      rethrow;
    } on http.ClientException catch (e) {
      if (abort.aborted) throw TransferAbortedException(request.url);
      throw ServerUnreachableException(e);
    }
  }

  Future<String> _readBody(http.StreamedResponse response, _Abort abort) async {
    final url = response.request?.url ?? _config.httpBase;
    try {
      final bytes = await abort.race(response.stream.toBytes(), url);
      return utf8.decode(bytes, allowMalformed: true);
    } on http.ClientException catch (e) {
      if (abort.aborted) throw TransferAbortedException(url);
      throw ServerUnreachableException(e);
    }
  }

  static Future<void> _discard(http.StreamedResponse response) =>
      response.stream.drain<void>().then((_) {}, onError: (_) {});

  static Json? _ctrlOf(String body) {
    try {
      if (jsonDecode(body) case {'ctrl': final Json ctrl}) return ctrl;
    } on FormatException {
      // Not JSON, e.g. a proxy's error page.
    }
    return null;
  }

  static ServerException _rejection(Json ctrl, int code) {
    final j = LooseJson(ctrl);
    return ServerException(
      code,
      j.get('text') ?? '',
      params: j.get('params') ?? const {},
    );
  }

  static http.MediaType? _mediaType(String? mimeType) {
    if (mimeType == null) return null;
    try {
      return http.MediaType.parse(mimeType);
    } on FormatException {
      return null;
    }
  }

  /// [expires] on this device's clock: the server's lifetime of the
  /// upload ([expires] minus the reply's [serverNow]) from now, so a device
  /// clock that is off doesn't make every upload look expired.
  static DateTime? _localExpiry(DateTime? expires, DateTime? serverNow) {
    if (expires == null || serverNow == null) return expires;
    return DateTime.now().toUtc().add(expires.difference(serverNow));
  }

  /// The server writes upload expiry in UTC without saying so.
  static DateTime? _serverTime(String? value) {
    if (value == null) return null;
    final zoned = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(value);
    return DateTime.tryParse(zoned ? value : '${value}Z');
  }
}

/// One transfer's `abortTrigger`, applied to every request and stream of
/// it, even with HTTP clients that ignore it.
final class _Abort {
  _Abort(this.future) {
    unawaited(
      future?.then((_) {
        aborted = true;
        for (final listener in _listeners) {
          listener();
        }
        _listeners.clear();
      }, onError: (_) {}),
    );
  }

  final Future<void>? future;
  bool aborted = false;
  final _listeners = <void Function()>[];

  /// [work], unless the trigger fires first.
  Future<T> race<T>(Future<T> work, Uri url) {
    if (future == null) return work;
    final result = Completer<T>();
    void finish(void Function() complete) {
      if (!result.isCompleted) complete();
    }

    unawaited(
      work.then(
        (value) => finish(() => result.complete(value)),
        onError: (Object e, StackTrace s) =>
            finish(() => result.completeError(e, s)),
      ),
    );
    _onAbort(
      () => finish(() => result.completeError(TransferAbortedException(url))),
    );
    return result.future;
  }

  /// [source], ending in [TransferAbortedException] once the trigger fires.
  Stream<List<int>> guard(Stream<List<int>> source, Uri url) {
    if (future == null) return source;
    StreamSubscription<List<int>>? subscription;
    late final StreamController<List<int>> controller;
    void stop() {
      unawaited(subscription?.cancel());
      if (!controller.isClosed) {
        controller.addError(TransferAbortedException(url));
        unawaited(controller.close());
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        if (aborted) return stop();
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        _onAbort(stop);
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  void _onAbort(void Function() listener) {
    if (aborted) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}
