import 'dart:async';

/// Spots a socket that died without closing. After [idle] of silence it
/// sends a probe; if [timeout] passes with no frame at all, `onDead` runs.
final class Heartbeat {
  Heartbeat({
    required this.idle,
    required this.timeout,
    required void Function() probe,
    required void Function() onDead,
  }) : _probe = probe,
       _onDead = onDead {
    _check();
  }

  /// Null: probe only on [probeNow].
  final Duration? idle;
  final Duration timeout;
  final void Function() _probe;
  final void Function() _onDead;

  /// Time since the last frame, or since the probe while one is out.
  final _quiet = Stopwatch()..start();
  var _probing = false;
  late Duration _deadline = timeout;
  Timer? _timer;

  /// Any frame proves the socket alive; called per frame, so no timers.
  void frame() {
    _quiet.reset();
    _probing = false;
  }

  /// Sends a probe now; [timeout] overrides the deadline for this one only.
  void probeNow({Duration? timeout}) {
    _probing = true;
    _deadline = timeout ?? this.timeout;
    _quiet.reset();
    _probe();
    _schedule(_deadline);
  }

  void stop() => _timer?.cancel();

  void _check() {
    final quiet = _quiet.elapsed;
    if (_probing) {
      quiet >= _deadline ? _onDead() : _schedule(_deadline - quiet);
    } else if (idle case final idle?) {
      quiet >= idle ? probeNow() : _schedule(idle - quiet);
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _check);
  }
}
