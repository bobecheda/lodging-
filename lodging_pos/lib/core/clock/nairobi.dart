/// Times are stored in UTC and displayed in Africa/Nairobi, which is UTC+3
/// all year (no daylight saving), so a fixed offset is exact.
const nairobiOffset = Duration(hours: 3);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Wall-clock Nairobi time for [utc]. Only for display; never store it.
DateTime toNairobi(DateTime utc) => utc.toUtc().add(nairobiOffset);

/// e.g. `14 Oct 2026, 22:05`.
String formatNairobi(DateTime utc) {
  final t = toNairobi(utc);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, '
      '${two(t.hour)}:${two(t.minute)}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

/// Copy rule: dates as `Thu 15 Oct`.
String formatDayDate(DateTime utc) {
  final t = toNairobi(utc);
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}

/// Copy rule: 24-hour times, `07:02`.
String formatTime(DateTime utc) {
  final t = toNairobi(utc);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// `Thu 15 Oct · 07:02`.
String formatDayDateTime(DateTime utc) =>
    '${formatDayDate(utc)} · ${formatTime(utc)}';

/// "Good morning" before noon, "Good afternoon" until 17:00, then
/// "Good evening" (Nairobi time).
String greetingFor(DateTime utc) {
  final hour = toNairobi(utc).hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}
