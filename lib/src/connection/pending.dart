import 'dart:async';

import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/protocol/server/server_message.dart';

/// A request waiting for its reply; error replies fail it.
final class PendingRequest {
  PendingRequest(this.type);

  /// The packet type, named in timeout errors.
  final String type;
  final _completer = Completer<ServerMessage>();
  Timer? _timer;

  /// Completes with the reply or its error.
  Future<ServerMessage> get future => _completer.future;

  /// Starts the timeout that fails this request.
  void startTimer(Duration timeout, void Function() onTimeout) {
    _timer = Timer(timeout, () {
      onTimeout();
      fail(RequestTimeoutException(type, timeout));
    });
  }

  /// Completes with [reply], failing on error ctrls.
  void complete(ServerMessage reply) => switch (reply) {
    CtrlMessage(isError: true, :final code, :final text, :final params) => fail(
      ServerException(code, text, params: params),
    ),
    _ => _finish(() => _completer.complete(reply)),
  };

  /// Fails this request with [error].
  void fail(TinodeException error) =>
      _finish(() => _completer.completeError(error));

  /// Cancels the timer and settles the request once.
  void _finish(void Function() settle) {
    _timer?.cancel();
    if (!_completer.isCompleted) settle();
  }
}

/// Collects history `data` packets for one topic until its `get` settles.
/// Only seqs in `since <= seq < before` belong to it: a live message
/// outside that window is not history.
final class HistoryCollector {
  HistoryCollector({this.since, this.before});

  final int? since;
  final int? before;
  final _bySeq = <int, DataMessage>{};
  final _done = Completer<void>();

  /// The collected messages, oldest first, one per seq.
  List<DataMessage> get messages =>
      _bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

  /// Whether [seq] lies in the requested window.
  bool accepts(int seq) =>
      (since == null || seq >= since!) && (before == null || seq < before!);

  void add(DataMessage message) => _bySeq[message.seq] = message;

  /// Completes when the collection ends.
  Future<void> get done => _done.future;

  /// Ends the collection.
  void finish() => _done.complete();
}
