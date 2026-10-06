import 'package:meta/meta.dart';

/// How a dropped connection is retried. Each wait is random in
/// `[0, min(cap, base · 2^attempt))`, so clients that dropped together
/// don't come back together.
@immutable
final class ReconnectPolicy {
  const ReconnectPolicy({
    this.base = const Duration(seconds: 1),
    this.cap = const Duration(seconds: 30),
  }) : enabled = true;

  /// A drop is final, as it was before reconnection existed.
  const ReconnectPolicy.disabled()
    : base = Duration.zero,
      cap = Duration.zero,
      enabled = false;

  final Duration base;
  final Duration cap;
  final bool enabled;
}
