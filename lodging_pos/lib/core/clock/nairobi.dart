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
