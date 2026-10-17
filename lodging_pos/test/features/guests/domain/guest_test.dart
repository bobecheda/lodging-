import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';

GuestForm form({
  String fullName = 'Grace Achieng',
  String phone = '0722 418 905',
  IdType? idType,
  String idNumber = '',
}) => GuestForm(
  fullName: fullName,
  phone: phone,
  idType: idType,
  idNumber: idNumber,
);

void main() {
  group('validateGuest (FD-3)', () {
    test('full name and phone are enough', () {
      expect(validateGuest(form()), isEmpty);
    });

    test('name and phone are required', () {
      expect(validateGuest(form(fullName: ' ', phone: '')), {
        GuestField.fullName: 'Enter the full name.',
        GuestField.phone: 'Enter a phone number.',
      });
      expect(validateGuest(form(fullName: 'x' * 81)), {
        GuestField.fullName: 'Use at most 80 characters.',
      });
    });

    test('an international phone is fine for guests', () {
      expect(validateGuest(form(phone: '+256 712 345 678')), isEmpty);
    });

    test('an ID number needs its type', () {
      expect(validateGuest(form(idNumber: '12343921')), {
        GuestField.idType: 'Choose the ID type.',
      });
    });

    test('National ID: 6–9 digits', () {
      for (final ok in ['123456', '12343921', '123 456 789']) {
        expect(
          validateGuest(form(idType: IdType.nationalId, idNumber: ok)),
          isEmpty,
          reason: ok,
        );
      }
      for (final bad in ['12345', '1234567890', 'A1234567']) {
        expect(validateGuest(form(idType: IdType.nationalId, idNumber: bad)), {
          GuestField.idNumber: 'A National ID is 6–9 digits.',
        }, reason: bad);
      }
    });

    test('Passport and Alien ID: 6–12 letters and digits', () {
      expect(
        validateGuest(form(idType: IdType.passport, idNumber: 'ak 1234567')),
        isEmpty,
      );
      expect(
        validateGuest(form(idType: IdType.alienId, idNumber: '123456789012')),
        isEmpty,
      );
      expect(validateGuest(form(idType: IdType.passport, idNumber: 'AK12')), {
        GuestField.idNumber: 'A passport number is 6–12 letters and digits.',
      });
      expect(
        validateGuest(form(idType: IdType.alienId, idNumber: 'AB-12345')),
        {GuestField.idNumber: 'An Alien ID is 6–12 letters and digits.'},
      );
    });

    test('a type with no number is simply no ID', () {
      expect(validateGuest(form(idType: IdType.passport)), isEmpty);
      expect(form(idType: IdType.passport).normalized().idType, isNull);
    });

    test('normalized: trimmed name, stored phone, ID without spaces in '
        'capitals', () {
      final n = form(
        fullName: '  Grace   Achieng ',
        phone: '+254 722 418 905',
        idType: IdType.passport,
        idNumber: ' ak 123 4567 ',
      ).normalized();
      expect(n.fullName, 'Grace Achieng');
      expect(n.phone, '0722418905');
      expect((n.idType, n.idNumber), (IdType.passport, 'AK1234567'));
    });
  });

  test('ID types are stored by code and shown by label', () {
    expect(
      [for (final t in IdType.values) t.code],
      ['national_id', 'passport', 'alien_id'],
    );
    expect(IdType.parse('alien_id'), IdType.alienId);
    expect(IdType.nationalId.label, 'National ID');
  });

  group('GuestQuery (search as you type)', () {
    test('a phone, in any form, searches by its stored prefix', () {
      expect(GuestQuery.parse('0722 41').phonePrefix, '072241');
      expect(GuestQuery.parse('+254 722').phonePrefix, '0722');
      expect(GuestQuery.parse('254722').phonePrefix, '0722');
      expect(GuestQuery.parse('+256 71').phonePrefix, '+25671');
    });

    test('an ID searches by its normalized prefix', () {
      expect(GuestQuery.parse('ak 12').idPrefix, 'AK12');
      // Digits could be either, so both are searched.
      final q = GuestQuery.parse('1234');
      expect((q.phonePrefix, q.idPrefix), ('1234', '1234'));
    });

    test('fewer than 3 characters, or a name, searches nothing', () {
      expect(GuestQuery.parse('07').isEmpty, isTrue);
      expect(GuestQuery.parse(' ').isEmpty, isTrue);
      expect(GuestQuery.parse('Grace A').isEmpty, isTrue);
    });
  });

  test('earlier stays, on the returning guest’s card (FD-4)', () {
    // Fri 2 Oct 2026, 19:00 Nairobi.
    final last = DateTime.utc(2026, 10, 2, 16);
    expect(
      const GuestHistory(stays: 0, lastCheckIn: null).summary,
      'No earlier stays',
    );
    expect(
      GuestHistory(stays: 1, lastCheckIn: last).summary,
      '1 earlier stay · last on Fri 2 Oct',
    );
    expect(
      GuestHistory(stays: 3, lastCheckIn: last).summary,
      '3 earlier stays · last on Fri 2 Oct',
    );
  });
}
