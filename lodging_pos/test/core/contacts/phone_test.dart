import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/contacts/phone.dart';

void main() {
  group('normalizePhone (Kenyan numbers, stored as 10 digits)', () {
    test(
      'accepts local and international forms, ignoring spaces and dashes',
      () {
        for (final input in [
          '0722123310',
          '0722 123 310',
          '0722-123-310',
          '+254722123310',
          '+254 722 123 310',
          '254722123310',
        ]) {
          expect(normalizePhone(input), '0722123310', reason: input);
        }
        expect(normalizePhone('0110 234 567'), '0110234567');
        expect(normalizePhone('+254110234567'), '0110234567');
      },
    );

    test('accepts only 07… and 01… after converting', () {
      for (final bad in [
        '0822123310', // not 07/01
        '072212331', // 9 digits
        '07221233100', // 11 digits
        '+255722123310', // another country
        '0722 12a 310',
        '(0722) 123 310', // brackets are not stripped
        '',
      ]) {
        expect(normalizePhone(bad), isNull, reason: bad);
      }
    });
  });

  group('phoneError', () {
    test('optional: blank is fine', () {
      expect(phoneError('   '), isNull);
      expect(phoneError(''), isNull);
    });

    test('required: blank is refused', () {
      expect(phoneError(' ', required: true), 'Enter a phone number.');
    });

    test('a wrong number says what is expected', () {
      expect(
        phoneError('12345'),
        'Enter a Kenyan number starting 07 or 01, e.g. 0722 123 310.',
      );
      expect(phoneError('+254 722 123 310'), isNull);
    });
  });

  group('maskPhone', () {
    test('lists show the first 4 and last 3 digits', () {
      expect(maskPhone('0722123310'), '0722 ••• 310');
    });

    test('audit entries use the compact form', () {
      expect(maskPhone('0722123310', compact: true), '0722•••310');
    });

    test('anything too short to mask safely is fully hidden', () {
      expect(maskPhone('12345'), '•••');
      expect(maskPhone('12345', compact: true), '•••');
    });
  });
}
