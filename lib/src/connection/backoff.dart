import 'dart:math';

/// Full-jitter exponential backoff, see `ReconnectPolicy`.
final class Backoff {
  Backoff({required this.base, required this.cap, Random? random})
    : _random = random ?? Random();

  final Duration base;
  final Duration cap;
  final Random _random;
  var _attempt = 0;

  Duration next() {
    // Past 2^20 the ceiling is the cap anyway; stop before ints overflow.
    final growth = 1 << min(_attempt++, 20);
    final ceiling = min(cap.inMicroseconds, base.inMicroseconds * growth);
    return Duration(microseconds: (_random.nextDouble() * ceiling).floor());
  }

  void reset() => _attempt = 0;
}
