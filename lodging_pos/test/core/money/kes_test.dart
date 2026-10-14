import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/money/kes.dart';

void main() {
  group('formatKes', () {
    test('groups thousands', () {
      expect(formatKes(0), 'KES 0');
      expect(formatKes(500), 'KES 500');
      expect(formatKes(1000), 'KES 1,000');
      expect(formatKes(1234567), 'KES 1,234,567');
    });

    test('shows negatives (shift variance) with a minus sign', () {
      expect(formatKes(-100), 'KES -100');
      expect(formatKes(-1500), 'KES -1,500');
    });
  });

  group('parseKes', () {
    test('accepts plain, grouped and prefixed whole amounts', () {
      expect(parseKes('1000'), 1000);
      expect(parseKes('1,000'), 1000);
      expect(parseKes('KES 1,000'), 1000);
      expect(parseKes('  kes 750 '), 750);
      expect(parseKes('0'), 0);
    });

    test('rejects blanks, decimals, negatives and text', () {
      for (final input in ['', '  ', '10.50', '-5', 'abc', '1,00,0x']) {
        expect(parseKes(input), isNull, reason: input);
      }
    });
  });
}
