import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';

void main() {
  test('Nairobi is UTC+3 with no daylight saving', () {
    final local = toNairobi(DateTime.utc(2026, 10, 14, 19));
    expect(
      [local.year, local.month, local.day, local.hour],
      [2026, 10, 14, 22],
    );
  });

  test('formats a UTC time as Nairobi date and time', () {
    expect(
      formatNairobi(DateTime.utc(2026, 10, 14, 19, 5)),
      '14 Oct 2026, 22:05',
    );
    // Crosses midnight in Nairobi.
    expect(
      formatNairobi(DateTime.utc(2026, 12, 31, 22, 30)),
      '1 Jan 2027, 01:30',
    );
  });

  test('copy-rule formats: Thu 15 Oct and 24-hour 07:02', () {
    // 04:02 UTC = 07:02 Nairobi, Thursday 15 Oct 2026.
    final t = DateTime.utc(2026, 10, 15, 4, 2);
    expect(formatDayDate(t), 'Thu 15 Oct');
    expect(formatTime(t), '07:02');
    expect(formatDayDateTime(t), 'Thu 15 Oct · 07:02');
  });

  test('greeting follows Nairobi time of day', () {
    String at(int nairobiHour) => greetingFor(
      DateTime.utc(2026, 10, 15).add(Duration(hours: nairobiHour - 3)),
    );
    expect(at(5), 'Good morning');
    expect(at(11), 'Good morning');
    expect(at(12), 'Good afternoon');
    expect(at(16), 'Good afternoon');
    expect(at(17), 'Good evening');
    expect(at(23), 'Good evening');
    expect(at(2), 'Good evening');
  });
}
