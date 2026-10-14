import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock.g.dart';

/// The only source of "now" in the app. Always returns UTC.
///
/// Inject it instead of calling `DateTime.now()` so tests control time.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock that only moves when told to. For tests.
class FixedClock implements Clock {
  FixedClock(DateTime now) : _now = now.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void set(DateTime now) => _now = now.toUtc();

  void advance(Duration by) => _now = _now.add(by);
}

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => const SystemClock();
