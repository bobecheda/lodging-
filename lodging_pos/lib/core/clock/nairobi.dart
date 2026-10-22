/// Times are stored in UTC and displayed in Africa/Nairobi, which is UTC+3
/// all year (no daylight saving), so a fixed offset is exact.
const nairobiOffset = Duration(hours: 3);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Wall-clock Nairobi time for [utc], for display and for applying
/// wall-clock rules. Its fields are Nairobi's; never store it.
DateTime toNairobi(DateTime utc) => utc.toUtc().add(nairobiOffset);

/// The UTC instant of a Nairobi wall-clock time.
DateTime nairobiInstant(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) => DateTime.utc(
  year,
  month,
  day,
  hour,
  minute,
  second,
).subtract(nairobiOffset);

/// [utc] moved by [days] Nairobi calendar days, keeping its wall-clock time.
/// Calendar arithmetic, not "+24 h", so it stays right by construction.
DateTime addNairobiDays(DateTime utc, int days) {
  final t = toNairobi(utc);
  return nairobiInstant(
    t.year,
    t.month,
    t.day + days,
    t.hour,
    t.minute,
    t.second,
  ).add(Duration(milliseconds: t.millisecond, microseconds: t.microsecond));
}

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

/// `Fri 10:00`: weekday and time, e.g. a stay's checkout on the bed board.
String formatWeekdayTime(DateTime utc) {
  final t = toNairobi(utc);
  return '${_weekdays[t.weekday - 1]} ${formatTime(utc)}';
}

/// `Thu 15 Oct · 07:02`.
String formatDayDateTime(DateTime utc) =>
    '${formatDayDate(utc)} · ${formatTime(utc)}';

/// `Thu 15 Oct, 07:02`: a check-in time or a check-out-by time.
String formatDayDateComma(DateTime utc) =>
    '${formatDayDate(utc)}, ${formatTime(utc)}';

/// `today 09:15`, `yesterday 18:40`, or `Thu 15 Oct, 09:15`: when something
/// happened, as seen at [now] (Nairobi calendar days).
String formatWhen(DateTime utc, {required DateTime now}) {
  final t = toNairobi(utc);
  final day = DateTime.utc(t.year, t.month, t.day);
  final n = toNairobi(now);
  final today = DateTime.utc(n.year, n.month, n.day);
  return switch (today.difference(day).inDays) {
    0 => 'today ${formatTime(utc)}',
    1 => 'yesterday ${formatTime(utc)}',
    _ => formatDayDateComma(utc),
  };
}

/// "Good morning" before noon, "Good afternoon" until 17:00, then
/// "Good evening" (Nairobi time).
String greetingFor(DateTime utc) {
  final hour = toNairobi(utc).hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}
