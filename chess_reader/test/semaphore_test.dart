import 'package:flutter_test/flutter_test.dart';

import 'package:chess_reader/core/async/semaphore.dart';

void main() {
  test('grants up to N permits immediately, then queues', () async {
    final sem = Semaphore(2);
    await sem.acquire();
    await sem.acquire();
    expect(sem.availablePermits, 0);

    var third = false;
    final pending = sem.acquire().then((_) => third = true);
    await Future<void>.delayed(Duration.zero);
    expect(third, isFalse, reason: 'third acquire must wait for a release');

    sem.release();
    await pending;
    expect(third, isTrue);
  });

  test('never lets more than N run concurrently', () async {
    const limit = 3;
    final sem = Semaphore(limit);
    var running = 0, peak = 0;
    final tasks = <Future<void>>[];
    for (var i = 0; i < 20; i++) {
      tasks.add(sem.withPermit(() async {
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        running--;
      }));
    }
    await Future.wait(tasks);
    expect(peak, lessThanOrEqualTo(limit));
    expect(running, 0);
  });

  test('serves waiters in FIFO order', () async {
    final sem = Semaphore(1);
    await sem.acquire(); // hold the only permit
    final order = <int>[];
    final waiters = [
      sem.acquire().then((_) => order.add(1)),
      sem.acquire().then((_) => order.add(2)),
      sem.acquire().then((_) => order.add(3)),
    ];
    sem.release(); // -> 1
    await waiters[0];
    sem.release(); // -> 2
    await waiters[1];
    sem.release(); // -> 3
    await waiters[2];
    expect(order, [1, 2, 3]);
  });

  test('withPermit releases even when the action throws', () async {
    final sem = Semaphore(1);
    await expectLater(
      sem.withPermit(() async => throw StateError('boom')),
      throwsStateError,
    );
    // Permit must be back so the next acquire succeeds without blocking.
    expect(sem.availablePermits, 1);
    await sem.acquire();
    expect(sem.availablePermits, 0);
  });
}
