import 'dart:async';

/// A minimal asynchronous counting semaphore.
///
/// Used to bound how many units of work run at once (e.g. how many book pages
/// are recognized concurrently, so at most N page rasters sit in memory).
/// [acquire] returns immediately while permits remain, otherwise it waits until
/// another holder calls [release]. Waiters are served in FIFO order.
class Semaphore {
  Semaphore(this._permits) : assert(_permits > 0);

  int _permits;
  final _waiters = <Completer<void>>[];

  /// Permits currently available (for tests/diagnostics).
  int get availablePermits => _permits;

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _permits++;
    }
  }

  /// Runs [action] holding one permit, releasing it even if [action] throws.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}
