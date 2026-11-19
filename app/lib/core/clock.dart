import 'dart:async';

/// A millisecond clock that can wait until a deadline, so tests never really wait.
abstract interface class Clock {
  /// Current time in milliseconds.
  int nowMs();

  /// Completes once [nowMs] reaches [deadlineMs].
  Future<void> sleepUntil(int deadlineMs);
}

/// Real monotonic time.
class SystemClock implements Clock {
  /// Creates a clock that starts at 0 now.
  SystemClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int nowMs() => _watch.elapsedMilliseconds;

  @override
  Future<void> sleepUntil(int deadlineMs) {
    final int delay = deadlineMs - nowMs();
    return delay > 0
        ? Future<void>.delayed(Duration(milliseconds: delay))
        : Future<void>.value();
  }
}

/// Manual clock: time moves only through [advance] or [drive].
class FakeClock implements Clock {
  /// Creates a clock at [startMs].
  FakeClock([int startMs = 0]) : _now = startMs;

  int _now;
  final List<(int, Completer<void>)> _waiters = <(int, Completer<void>)>[];

  @override
  int nowMs() => _now;

  @override
  Future<void> sleepUntil(int deadlineMs) {
    if (deadlineMs <= _now) {
      return Future<void>.value();
    }
    final Completer<void> done = Completer<void>();
    _waiters.add((deadlineMs, done));
    return done.future;
  }

  /// Moves time forward by [ms], waking every waiter that is now due.
  Future<void> advance(int ms) async {
    _now += ms;
    _release();
    await _settle();
  }

  void _release() {
    final List<(int, Completer<void>)> due = _waiters
        .where(((int, Completer<void>) w) => w.$1 <= _now)
        .toList();
    _waiters.removeWhere(((int, Completer<void>) w) => w.$1 <= _now);
    for (final (int, Completer<void>) w in due) {
      w.$2.complete();
    }
  }

  Future<void> _settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Runs [work], jumping time to the next deadline whenever everything is waiting.
  Future<T> drive<T>(Future<T> work) async {
    bool finished = false;
    late T result;
    Object? failure;
    StackTrace? trace;
    unawaited(
      work.then(
        (T v) {
          result = v;
          finished = true;
        },
        onError: (Object e, StackTrace s) {
          failure = e;
          trace = s;
          finished = true;
        },
      ),
    );
    while (!finished) {
      await _settle();
      if (finished) {
        break;
      }
      if (_waiters.isEmpty) {
        throw StateError(
          'FakeClock.drive: nothing is waiting, but the work has not finished',
        );
      }
      final int next = _waiters
          .map(((int, Completer<void>) w) => w.$1)
          .reduce((int a, int b) => a < b ? a : b);
      _now = next > _now ? next : _now;
      _release();
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, trace!);
    }
    return result;
  }
}
