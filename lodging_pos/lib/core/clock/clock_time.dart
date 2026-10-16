/// A wall-clock time of day (e.g. the 10:00 checkout), pure Dart so domain
/// code never needs Flutter's `TimeOfDay`. Stored in settings as `HH:MM`.
final class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// Minutes since midnight.
  int get inMinutes => hour * 60 + minute;

  /// Parses `HH:MM` (24-hour, two digits each); null if malformed.
  static ClockTime? tryParse(String text) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return ClockTime(hour, minute);
  }

  /// `10:00`.
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ClockTime other) => inMinutes - other.inMinutes;

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.inMinutes == inMinutes;

  @override
  int get hashCode => inMinutes;

  @override
  String toString() => format();
}
