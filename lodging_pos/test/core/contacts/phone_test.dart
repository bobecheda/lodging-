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

  group('guest phones (Kenyan first, then international)', () {
    test('Kenyan forms still become 07… / 01…', () {
      expect(normalizeGuestPhone('+254 722 123 310'), '0722123310');
      expect(normalizeGuestPhone('254110234567'), '0110234567');
      expect(normalizeGuestPhone('0722-123-310'), '0722123310');
    });

    test('international: + then 8–15 digits, stored as + and digits', () {
      expect(normalizeGuestPhone('+256 712 345 678'), '+256712345678');
      expect(normalizeGuestPhone('+44 20-7946-0958'), '+442079460958');
      expect(normalizeGuestPhone('+12345678'), '+12345678');
      expect(normalizeGuestPhone('+123456789012345'), '+123456789012345');
    });

    test('anything else is refused', () {
      for (final bad in [
        '+1234567', // 7 digits
        '+1234567890123456', // 16 digits
        '256712345678', // international needs the +
        '0822123310',
        '+256 7123a5678',
        '',
      ]) {
        expect(normalizeGuestPhone(bad), isNull, reason: bad);
      }
    });

    test('guests must give a phone', () {
      expect(guestPhoneError(''), 'Enter a phone number.');
      expect(
        guestPhoneError('12345'),
        'Enter a Kenyan number (07…, 01…) or an international one starting '
        'with +.',
      );
      expect(guestPhoneError('+256 712 345 678'), isNull);
    });

    test('housekeepers stay Kenyan-only', () {
      expect(normalizePhone('+256712345678'), isNull);
    });

    test('masks international numbers: first 4 and last 3 digits', () {
      expect(maskPhone('+256712345678'), '+2567 ••• 678');
      expect(maskPhone('+256712345678', compact: true), '+2567•••678');
    });
  });
}
