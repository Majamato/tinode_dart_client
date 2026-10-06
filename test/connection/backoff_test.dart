import 'dart:math';

import 'package:test/test.dart';
import 'package:tinode_dart_client/src/connection/backoff.dart';

/// Always draws the same fraction of the range.
final class FixedRandom implements Random {
  FixedRandom(this.fraction);

  final double fraction;

  @override
  double nextDouble() => fraction;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  int nextInt(int max) => throw UnimplementedError();
}

Backoff backoff(double fraction) => Backoff(
  base: const Duration(seconds: 1),
  cap: const Duration(seconds: 30),
  random: FixedRandom(fraction),
);

void main() {
  test('the ceiling doubles per attempt up to the cap', () {
    final b = backoff(1);
    expect(
      [for (var i = 0; i < 7; i++) b.next().inSeconds],
      [1, 2, 4, 8, 16, 30, 30],
    );
  });

  test('waits are a random share of the ceiling', () {
    final b = backoff(0.25);
    expect(
      [for (var i = 0; i < 3; i++) b.next()],
      const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
        Duration(seconds: 1),
      ],
    );
    expect(backoff(0).next(), Duration.zero);
  });

  test('reset starts over from the base', () {
    final b = backoff(1)
      ..next()
      ..next()
      ..reset();
    expect(b.next(), const Duration(seconds: 1));
  });

  test('stays capped after many attempts', () {
    final b = backoff(1);
    for (var i = 0; i < 100; i++) {
      b.next();
    }
    expect(b.next(), const Duration(seconds: 30));
  });
}
