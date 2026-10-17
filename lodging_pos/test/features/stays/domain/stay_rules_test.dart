import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

/// Nairobi wall-clock time in October 2026 (Thu 15, Fri 16, … Sun 25), as
/// the UTC instant the app stores.
DateTime oct(int day, int hour, [int minute = 0, int second = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute, second);

const checkout = ClockTime(10, 0);
const grace = 60;
const price = 700;

/// Bed 3A, Deluxe.
LetBed deluxeBed({int pricePerNight = price}) => LetBed(
  bedId: 'bed-3a',
  categoryId: 'deluxe',
  categoryName: 'Deluxe',
  pricePerNight: pricePerNight,
);

/// A stay on one bed, checked in at [checkInAt] for [nights].
Stay stayFrom(DateTime checkInAt, int nights, {int pricePerNight = price}) {
  final plan = planCheckIn(
    checkInAt: checkInAt,
    nights: nights,
    checkout: checkout,
    beds: [deluxeBed(pricePerNight: pricePerNight)],
  );
  return Stay.fromCheckIn(
    id: 'stay-1',
    bedId: 'bed-3a',
    charge: plan.stays.single.charge,
  );
}

BedSummary bed({
  bool isActive = true,
  Cleanliness cleanliness = Cleanliness.clean,
}) => BedSummary(
  id: 'bed-3a',
  label: BedLabel.a,
  categoryId: 'deluxe',
  categoryName: 'Deluxe',
  pricePerNight: 700,
  cleanliness: cleanliness,
  isActive: isActive,
  hasActiveStay: false,
);

void main() {
  test('required test case 1: Thu 19:00, 1 night → Fri 10:00, total = '
      'price', () {
    final first = firstCheckout(oct(15, 19), checkout);
    expect(first, oct(16, 10));
    expect(first.isUtc, isTrue);
    expect(paidUntil(first, 1), oct(16, 10));
    expect(totalDue(1, price), 700);
  });

  test('required test case 2: any daytime arrival checks out 10:00 the next '
      'day', () {
    for (final arrival in [oct(15, 13), oct(15, 7), oct(15, 9, 59)]) {
      expect(firstCheckout(arrival, checkout), oct(16, 10), reason: '$arrival');
    }
  });

  test('required test case 3: early-morning and late-night arrivals also '
      'check out 10:00 the next calendar day', () {
    expect(firstCheckout(oct(15, 3), checkout), oct(16, 10));
    expect(firstCheckout(oct(15, 0, 30), checkout), oct(16, 10));
    expect(firstCheckout(oct(14, 23, 59), checkout), oct(15, 10));
  });

  test('required test case 4: Thu 15 Oct 19:00, 10 nights → paid until '
      'Sun 25 Oct 10:00, total 10 × price', () {
    final first = firstCheckout(oct(15, 19), checkout);
    expect(paidUntil(first, 10), oct(25, 10));
    expect(totalDue(10, price), 7000);

    final charge = stayFrom(oct(15, 19), 10).charges.single;
    expect(charge.kind, ChargeKind.checkIn);
    expect(charge.nights, 10);
    expect(charge.amount, 7000);
    expect(charge.periodStart, oct(15, 19));
    expect(charge.periodEnd, oct(25, 10));
  });

  test('required test case 5: overstay starts after paid_until + grace', () {
    final stay = stayFrom(oct(15, 19), 1); // paid until Fri 10:00
    Occupancy at(DateTime now) =>
        occupancyOf(activeStay: stay, now: now, graceMinutes: grace);

    expect(at(oct(16, 10, 59)), Occupancy.occupied);
    expect(at(oct(16, 11)), Occupancy.occupied);
    expect(at(oct(16, 11, 0, 1)), Occupancy.overstay);
    expect(
      occupancyOf(activeStay: null, now: oct(16, 11), graceMinutes: grace),
      Occupancy.available,
    );
  });

  test('required test case 6: an extension entered at 11:40 counts from '
      'paid_until, not from now', () {
    final stay = stayFrom(oct(15, 19), 1); // paid until Fri 10:00
    // Entered Fri 11:40, during the overstay: the time of entry doesn't
    // matter, the new night runs from the paid-until 10:00.
    final extension = extensionCharge(stay, 1);
    expect(extension.kind, ChargeKind.extension);
    expect(extension.periodStart, oct(16, 10));
    expect(extension.periodEnd, oct(17, 10));
    expect(extension.amount, 700);
    expect(stay.withCharge(extension).paidUntil, oct(17, 10));
  });

  test('required test case 7: a later category price change does not touch '
      'the stay', () {
    final stay = stayFrom(oct(15, 19), 10, pricePerNight: 700);
    // The owner raises Deluxe 700 → 750 after this check-in. None of the
    // rules take the category price: they all read the stay's own.
    const deluxeNow = 750;
    expect(deluxeNow, isNot(stay.pricePerNight));

    expect(extensionCharge(stay, 1).pricePerNight, 700);
    final late = lateCheckoutCharge(stay, oct(25, 11, 30), grace)!;
    expect((late.pricePerNight, late.amount), (700, 700));
    final refund = earlyCheckoutRefund(stay, oct(21, 15), grace)!;
    expect((refund.pricePerNight, refund.amount), (700, 2100));
  });

  test('later charges keep the check-in charge’s category, like its price', () {
    // Even if the bed moves to another category after check-in.
    final stay = stayFrom(oct(15, 19), 2);
    final extension = extensionCharge(stay, 1);
    final late = lateCheckoutCharge(stay, oct(17, 11, 30), grace)!;
    for (final charge in [extension, late]) {
      expect((charge.categoryId, charge.categoryName), ('deluxe', 'Deluxe'));
    }
    expect(stay.categoryName, 'Deluxe');
  });

  group('required test case 8: late checkout', () {
    final stay = stayFrom(oct(15, 19), 1); // paid until Fri 10:00

    test('within grace (10:45) is free', () {
      expect(lateNights(stay.paidUntil, oct(16, 10, 45), grace), 0);
      expect(lateCheckoutCharge(stay, oct(16, 10, 45), grace), isNull);
    });

    test('at 11:30 one night is charged and paid_until moves forward', () {
      expect(lateNights(stay.paidUntil, oct(16, 11, 30), grace), 1);
      final charge = lateCheckoutCharge(stay, oct(16, 11, 30), grace)!;
      expect(charge.kind, ChargeKind.lateCheckout);
      expect((charge.nights, charge.amount), (1, 700));
      expect(charge.periodStart, oct(16, 10));
      expect(charge.periodEnd, oct(17, 10));
      expect(stay.withCharge(charge).paidUntil, oct(17, 10));
    });

    test('two days late at 12:00 charges 3 nights', () {
      expect(lateNights(stay.paidUntil, oct(18, 12), grace), 3);
      final charge = lateCheckoutCharge(stay, oct(18, 12), grace)!;
      expect((charge.nights, charge.amount), (3, 2100));
      expect(charge.periodEnd, oct(19, 10));
    });
  });

  test('required test case 9: 10 nights from Thu 19:00, leaving Wed 21 Oct '
      '15:00 → 7 used, refund request for 3', () {
    final stay = stayFrom(oct(15, 19), 10);
    final used = nightsUsed(stay.firstCheckout, oct(21, 15), grace, 10);
    expect(used, 7);
    expect(refundNights(10, used), 3);
    expect(refundAmount(3, price), 2100);

    final refund = earlyCheckoutRefund(stay, oct(21, 15), grace)!;
    expect(
      (refund.nights, refund.pricePerNight, refund.amount),
      (3, 700, 2100),
    );
  });

  test('required test case 10: the night in progress is never refunded', () {
    final stay = stayFrom(oct(15, 19), 10);
    // Fri 10:30: still within the first night's grace → 1 used, 9 back.
    expect(nightsUsed(stay.firstCheckout, oct(16, 10, 30), grace, 10), 1);
    expect(earlyCheckoutRefund(stay, oct(16, 10, 30), grace)!.nights, 9);
    // Fri 11:30: night 2 has started → 2 used, 8 back.
    expect(nightsUsed(stay.firstCheckout, oct(16, 11, 30), grace, 10), 2);
    expect(earlyCheckoutRefund(stay, oct(16, 11, 30), grace)!.nights, 8);
  });

  test('required test case 11: a 1-night stay leaving early gets nothing '
      'back and no refund request', () {
    final stay = stayFrom(oct(15, 19), 1);
    final used = nightsUsed(stay.firstCheckout, oct(16, 8), grace, 1);
    expect(refundNights(1, used), 0);
    expect(earlyCheckoutRefund(stay, oct(16, 8), grace), isNull);
  });

  test('required test case 14: both beds for one guest → two stays, one '
      'payment for the sum', () {
    final plan = planCheckIn(
      checkInAt: oct(15, 19),
      nights: 2,
      checkout: checkout,
      beds: [
        deluxeBed(),
        const LetBed(
          bedId: 'bed-3b',
          categoryId: 'normal',
          categoryName: 'Normal',
          pricePerNight: 500,
        ),
      ],
    );
    expect([for (final s in plan.stays) s.bedId], ['bed-3a', 'bed-3b']);
    expect([for (final s in plan.stays) s.charge.amount], [1400, 1000]);
    // Each charge keeps its own bed's category (v2).
    expect(
      [
        for (final s in plan.stays)
          (s.charge.categoryId, s.charge.categoryName),
      ],
      [('deluxe', 'Deluxe'), ('normal', 'Normal')],
    );
    expect(plan.paymentAmount, 2400);
    for (final s in plan.stays) {
      expect(s.charge.periodStart, oct(15, 19));
      expect(s.charge.periodEnd, oct(17, 10));
    }
  });

  test('required test case 15: only an active, available, clean bed can be '
      'let', () {
    expect(canLet(bed(), Occupancy.available), isTrue);
    expect(
      canLet(bed(cleanliness: Cleanliness.notCleaned), Occupancy.available),
      isFalse,
    );
    expect(canLet(bed(isActive: false), Occupancy.available), isFalse);
    expect(canLet(bed(), Occupancy.occupied), isFalse);
    expect(canLet(bed(), Occupancy.overstay), isFalse);
  });

  group('guards', () {
    test('a stay is at least one night', () {
      expect(
        () => planCheckIn(
          checkInAt: oct(15, 19),
          nights: 0,
          checkout: checkout,
          beds: [deluxeBed()],
        ),
        throwsArgumentError,
      );
      expect(
        () => extensionCharge(stayFrom(oct(15, 19), 1), 0),
        throwsArgumentError,
      );
    });

    test('nights used never exceeds nights paid', () {
      final stay = stayFrom(oct(15, 19), 2);
      expect(nightsUsed(stay.firstCheckout, oct(20, 9), grace, 2), 2);
      expect(earlyCheckoutRefund(stay, oct(20, 9), grace), isNull);
    });

    test('a different checkout time moves every rule with it', () {
      final first = firstCheckout(oct(15, 19), const ClockTime(11, 30));
      expect(first, oct(16, 11, 30));
      expect(paidUntil(first, 3), oct(18, 11, 30));
    });
  });
}
