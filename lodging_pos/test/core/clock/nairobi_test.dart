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
}
