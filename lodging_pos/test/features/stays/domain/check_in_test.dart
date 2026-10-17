import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

DateTime oct(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

const ten = ClockTime(10, 0);

const deluxeA = LetBed(
  bedId: 'bed-7a',
  categoryId: 'deluxe',
  categoryName: 'Deluxe',
  pricePerNight: 700,
);
const comfortB = LetBed(
  bedId: 'bed-7b',
  categoryId: 'comfort',
  categoryName: 'Comfort',
  pricePerNight: 600,
);

BedSummary bed({
  BedLabel label = BedLabel.b,
  bool isActive = true,
  Cleanliness cleanliness = Cleanliness.clean,
}) => BedSummary(
  id: 'bed-7b',
  label: label,
  categoryId: 'comfort',
  categoryName: 'Comfort',
  pricePerNight: 600,
  cleanliness: cleanliness,
  isActive: isActive,
  hasActiveStay: false,
);

void main() {
  group('nights (1–30)', () {
    test('1 and 30 are fine; anything else says the range', () {
      expect(nightsError(1), isNull);
      expect(nightsError(30), isNull);
      for (final n in [0, 31, -2]) {
        expect(nightsError(n), 'Choose 1 to 30 nights.', reason: '$n');
      }
      expect(nightsError(null), 'Enter the number of nights.');
    });

    test('typed nights: digits only', () {
      expect(parseNights(' 12 '), 12);
      expect(parseNights(''), isNull);
      expect(parseNights('2.5'), isNull);
      expect(parseNights('two'), isNull);
    });
  });

  group('letBlocker: why a bed can’t be let (BR-5)', () {
    test('says what to do, in the order a receptionist would check', () {
      expect(letBlocker(bed(), Occupancy.available), isNull);
      expect(
        letBlocker(bed(isActive: false), Occupancy.available),
        'Bed B is closed',
      );
      expect(letBlocker(bed(), Occupancy.occupied), 'Bed B has a guest');
      expect(letBlocker(bed(), Occupancy.overstay), 'Bed B has a guest');
      expect(
        letBlocker(
          bed(cleanliness: Cleanliness.notCleaned),
          Occupancy.available,
        ),
        'Bed B needs cleaning first',
      );
    });

    test('agrees with canLet', () {
      for (final b in [
        bed(),
        bed(isActive: false),
        bed(cleanliness: Cleanliness.notCleaned),
      ]) {
        for (final o in Occupancy.values) {
          expect(letBlocker(b, o) == null, canLet(b, o));
        }
      }
    });
  });

  group('quote: what the screen shows', () {
    test('one bed, 2 nights from Thu 11:24: Sat 10:00, 2 × KES 700', () {
      final q = quoteCheckIn(
        checkInAt: oct(15, 11, 24),
        nights: 2,
        checkout: ten,
        beds: const [deluxeA],
      );
      expect(q.paidUntil, oct(17, 10));
      expect(q.total, 1400);
      expect(q.plan.stays.single.charge.categoryName, 'Deluxe');
    });

    test('both beds: one total for two stays', () {
      final q = quoteCheckIn(
        checkInAt: oct(15, 19),
        nights: 3,
        checkout: ten,
        beds: const [deluxeA, comfortB],
      );
      expect(q.total, 3 * 700 + 3 * 600);
      expect(q.plan.stays, hasLength(2));
    });
  });

  group('quoteChange: a save never records what the screen didn’t show', () {
    CheckInQuote quote(
      DateTime at, {
      List<LetBed> beds = const [deluxeA],
      ClockTime checkout = ten,
    }) =>
        quoteCheckIn(checkInAt: at, nights: 1, checkout: checkout, beds: beds);

    test('nothing changed (minutes later, same day): fine', () {
      expect(quoteChange(quote(oct(16, 19)), quote(oct(16, 19, 40))), isNull);
    });

    test('opened Fri 23:58, saved Sat 00:01: checkout moved to Sun', () {
      expect(
        quoteChange(quote(oct(16, 23, 58)), quote(oct(17, 0, 1))),
        'It’s now past midnight, so checkout is Sun 18 Oct, 10:00. Check and '
        'save again.',
      );
    });

    test('the checkout time setting changed while the screen was open', () {
      expect(
        quoteChange(
          quote(oct(16, 19)),
          quote(oct(16, 19, 5), checkout: const ClockTime(11, 0)),
        ),
        'Checkout is now 11:00, so this stay ends Sat 17 Oct, 11:00. Check '
        'and save again.',
      );
    });

    test('the price changed', () {
      const raised = LetBed(
        bedId: 'bed-7a',
        categoryId: 'deluxe',
        categoryName: 'Deluxe',
        pricePerNight: 750,
      );
      expect(
        quoteChange(quote(oct(16, 19)), quote(oct(16, 19), beds: [raised])),
        'Deluxe is now KES 750 a night. Check the total and save again.',
      );
    });

    test('the bed moved to another category', () {
      const moved = LetBed(
        bedId: 'bed-7a',
        categoryId: 'normal',
        categoryName: 'Normal',
        pricePerNight: 500,
      );
      expect(
        quoteChange(quote(oct(16, 19)), quote(oct(16, 19), beds: [moved])),
        'This bed is now Normal at KES 500 a night. Check the total and save '
        'again.',
      );
    });
  });

  group('validateCheckIn', () {
    CheckInRequest request({
      int nights = 1,
      List<LetBed> beds = const [deluxeA],
      PaymentMethod method = PaymentMethod.cash,
      String? code,
    }) => CheckInRequest(
      guest: const ReturningGuest('guest-1'),
      method: method,
      mpesaCode: code,
      shown: quoteCheckIn(
        checkInAt: oct(15, 19),
        nights: nights,
        checkout: ten,
        beds: beds,
      ),
    );

    test('a cash check-in for one bed is fine', () {
      expect(validateCheckIn(request(), codeUsedOn: null), isEmpty);
    });

    test('nights out of range', () {
      expect(validateCheckIn(request(nights: 31), codeUsedOn: null), {
        CheckInField.nights: 'Choose 1 to 30 nights.',
      });
    });

    test('M-Pesa needs an unused code (required test case 16)', () {
      expect(
        validateCheckIn(
          request(method: PaymentMethod.paybill),
          codeUsedOn: null,
        ),
        {CheckInField.mpesaCode: 'Enter the M-Pesa code.'},
      );
      expect(
        validateCheckIn(
          request(method: PaymentMethod.paybill, code: 'qjk7h2lm4p'),
          codeUsedOn: MpesaCodeUse(
            receiptNumber: 'R-000038',
            at: oct(15, 11, 2),
          ),
        ),
        {
          CheckInField.mpesaCode:
              'QJK7H2LM4P was already used on receipt R-000038 (Thu 15 Oct, '
              '11:02).',
        },
      );
      expect(validateCheckIn(request(code: 'QJK7H2LM4P'), codeUsedOn: null), {
        CheckInField.mpesaCode: 'Cash has no M-Pesa code.',
      });
    });

    test('one or two beds, never the same bed twice', () {
      expect(validateCheckIn(request(beds: const []), codeUsedOn: null), {
        CheckInField.beds: 'Choose a bed.',
      });
      expect(
        validateCheckIn(
          request(beds: const [deluxeA, deluxeA]),
          codeUsedOn: null,
        ),
        {CheckInField.beds: 'Choose a bed.'},
      );
    });

    test('a new guest’s form is checked too', () {
      final r = CheckInRequest(
        guest: const NewGuest(
          GuestForm(fullName: '', phone: '07', idType: null, idNumber: ''),
        ),
        method: PaymentMethod.cash,
        mpesaCode: null,
        shown: request().shown,
      );
      expect(validateCheckIn(r, codeUsedOn: null), {
        CheckInField.guest: 'Check the new guest’s details.',
      });
    });
  });

  test('the receipt summary of a check-in', () {
    expect(
      checkedInSummary(roomNumber: '7', labels: const [BedLabel.a]),
      'Room 7, Bed A',
    );
    expect(
      checkedInSummary(roomNumber: '7', labels: const [BedLabel.a, BedLabel.b]),
      'Room 7, Beds A and B',
    );
  });
}
