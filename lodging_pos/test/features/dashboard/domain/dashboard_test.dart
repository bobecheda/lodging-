import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';

DateTime oct(int day, [int hour = 0, int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

MoneyMove paid(
  DateTime at,
  int amount, {
  PaymentMethod method = PaymentMethod.cash,
  bool voided = false,
}) => MoneyMove(
  at: at,
  amount: amount,
  method: method,
  isPayout: false,
  voided: voided,
);

MoneyMove refunded(
  DateTime at,
  int amount, {
  PaymentMethod method = PaymentMethod.cash,
  bool voided = false,
}) => MoneyMove(
  at: at,
  amount: amount,
  method: method,
  isPayout: true,
  voided: voided,
);

void main() {
  group('days', () {
    test('Nairobi midnight, not UTC midnight', () {
      // 00:30 Nairobi on the 21st is 21:30 UTC on the 20th.
      expect(dayStart(oct(21, 0, 30)), oct(21));
      expect(dayStart(oct(21, 23, 59)), oct(21));
      expect(monthStart(oct(21, 9)), oct(1));
    });

    test('the same moment last month, clamped to a shorter month', () {
      expect(
        sameMomentLastMonth(oct(21, 9, 30)),
        nairobiInstant(2026, 9, 21, 9, 30),
      );
      expect(sameMomentLastMonth(oct(31, 18)), nairobiInstant(2026, 9, 30, 18));
      expect(
        sameMomentLastMonth(nairobiInstant(2026, 3, 30, 8)),
        nairobiInstant(2026, 2, 28, 8),
      );
      expect(
        sameMomentLastMonth(nairobiInstant(2026, 1, 15, 8)),
        nairobiInstant(2025, 12, 15, 8),
      );
    });

    test('names', () {
      expect(formatLongDate(oct(21, 9)), 'Wednesday 21 October');
      expect(monthName(oct(21, 9)), 'OCTOBER');
    });
  });

  group('net takings', () {
    test('payments − refunds paid − anything voided, by method, within the '
        'period (by Nairobi day)', () {
      final moves = [
        paid(oct(21, 8), 1400),
        paid(oct(21, 9), 2100, method: PaymentMethod.paybill),
        refunded(oct(21, 10), 700),
        refunded(oct(21, 11), 700, method: PaymentMethod.paybill),
        paid(oct(21, 12), 5000, voided: true),
        refunded(oct(21, 13), 600, voided: true),
        paid(oct(20, 23, 59), 999), // the day before, in Nairobi
        paid(oct(22, 0), 999), // the day after
      ];
      final t = takingsBetween(moves, from: oct(21), to: oct(22));
      expect((t.cash, t.mpesa, t.net), (700, 1400, 2100));
    });

    test('a refund counts on the day it is paid, not the day of the stay', () {
      final moves = [paid(oct(19, 20), 2100), refunded(oct(21, 9), 1400)];
      expect(takingsBetween(moves, from: oct(21), to: oct(22)).net, -1400);
      expect(takingsBetween(moves, from: oct(19), to: oct(20)).net, 2100);
    });
  });

  group("today's money", () {
    test('today so far against the same weekday last week up to the same '
        'time', () {
      final now = oct(21, 14); // Wednesday 14:00
      final moves = [
        paid(oct(21, 9), 9600),
        paid(oct(21, 13), 8800, method: PaymentMethod.paybill),
        paid(oct(14, 10), 16400), // last Wednesday before 14:00
        paid(oct(14, 18), 5000), // last Wednesday after 14:00: not counted
        paid(oct(13, 23), 7000), // the Tuesday
      ];
      final m = todaysMoney(moves, now);
      expect((m.today.cash, m.today.mpesa, m.today.net), (9600, 8800, 18400));
      expect(m.lastWeek, 16400);
      expect(vsLastWeekLine(m, now), '▲ 12% vs last Wednesday (KES 16,400)');
    });

    test('down, the same, or nothing to compare with', () {
      final now = oct(21, 14);
      String line(List<MoneyMove> moves) =>
          vsLastWeekLine(todaysMoney(moves, now), now);
      expect(
        line([paid(oct(21, 9), 900), paid(oct(14, 9), 1000)]),
        '▼ 10% vs last Wednesday (KES 1,000)',
      );
      expect(
        line([paid(oct(21, 9), 1000), paid(oct(14, 9), 1000)]),
        'Same vs last Wednesday (KES 1,000)',
      );
      expect(
        line([paid(oct(21, 9), 1000)]),
        'Nothing taken by now last Wednesday',
      );
    });
  });

  group('beds right now', () {
    test('in use = occupied + overstay, of every active bed', () {
      final beds = BedsNow.fromCounts({
        BoardStatus.occupied: 17,
        BoardStatus.overstay: 1,
        BoardStatus.toClean: 2,
        BoardStatus.ready: 4,
      });
      expect((beds.inUse, beds.total, beds.percentInUse), (18, 24, 75));
    });

    test('no beds yet', () {
      expect(BedsNow.fromCounts(const {}).percentInUse, isNull);
    });
  });

  group('occupancy', () {
    test("a night belongs to the date it starts: a Thursday 19:00 check-in "
        "for 2 nights sells Thursday's and Friday's", () {
      final stay = StayNights(
        charges: [
          ChargeNights(
            nights: 2,
            periodEnd: oct(17, 10),
            categoryName: 'Deluxe',
            pricePerNight: 700,
          ),
        ],
      );
      expect(soldNightDates(stay), [
        DateTime.utc(2026, 10, 15),
        DateTime.utc(2026, 10, 16),
      ]);
    });

    test('an extension adds its nights; a refund takes back the last ones '
        'unless rejected; a voided stay sells nothing', () {
      final extended = StayNights(
        charges: [
          ChargeNights(
            nights: 1,
            periodEnd: oct(16, 10),
            categoryName: 'Deluxe',
            pricePerNight: 700,
          ),
          ChargeNights(
            nights: 4,
            periodEnd: oct(20, 10),
            categoryName: 'Deluxe',
            pricePerNight: 700,
          ), // 16–19
        ],
        refundedNights: 2, // left early: 18 and 19 not used
      );
      expect(soldNightDates(extended), [
        DateTime.utc(2026, 10, 15),
        DateTime.utc(2026, 10, 16),
        DateTime.utc(2026, 10, 17),
      ]);
      expect(
        soldNightDates(
          StayNights(
            charges: [
              ChargeNights(
                nights: 3,
                periodEnd: oct(18, 10),
                categoryName: 'Deluxe',
                pricePerNight: 700,
              ),
            ],
            voided: true,
          ),
        ),
        isEmpty,
      );
    });

    test('sold ÷ active bed-nights over a date range; a stay crossing the '
        'month end counts only its nights inside', () {
      final stays = [
        // 29 Sep – 2 Oct: 30 Sep... nights 29, 30 Sep and 1 Oct.
        StayNights(
          charges: [
            ChargeNights(
              nights: 3,
              periodEnd: nairobiInstant(2026, 10, 2, 10),
              categoryName: 'Deluxe',
              pricePerNight: 700,
            ),
          ],
        ),
        StayNights(
          charges: [
            ChargeNights(
              nights: 2,
              periodEnd: oct(5, 10),
              categoryName: 'Deluxe',
              pricePerNight: 700,
            ),
          ],
        ),
      ];
      final sold = bedNightsSold(
        stays,
        first: DateTime.utc(2026, 10, 1),
        last: DateTime.utc(2026, 10, 4),
      );
      expect(sold, 3); // 1 Oct + 3 and 4 Oct
      expect(occupancyPercent(sold: sold, activeBeds: 2, nights: 4), 38);
      expect(occupancyPercent(sold: 0, activeBeds: 0, nights: 4), isNull);
    });
  });

  group('this month', () {
    test('revenue and occupancy so far against the same point last month', () {
      final now = oct(21, 9, 30);
      final moves = [
        paid(oct(1, 9), 300000),
        paid(oct(21, 9), 112600),
        paid(oct(21, 10), 5000), // after now
        paid(nairobiInstant(2026, 9, 10, 9), 382100),
        paid(nairobiInstant(2026, 9, 25, 9), 50000), // after 21 Sep 09:30
      ];
      // One bed, sold every night 1–21 Oct, and 1–7 Sep.
      final stays = [
        StayNights(
          charges: [
            ChargeNights(
              nights: 21,
              periodEnd: oct(22, 10),
              categoryName: 'Deluxe',
              pricePerNight: 700,
            ),
          ],
        ),
        StayNights(
          charges: [
            ChargeNights(
              nights: 7,
              periodEnd: nairobiInstant(2026, 9, 8, 10),
              categoryName: 'Deluxe',
              pricePerNight: 700,
            ),
          ],
        ),
      ];
      final m = thisMonth(moves: moves, stays: stays, activeBeds: 1, now: now);
      expect((m.revenue, m.revenueLastMonth), (412600, 382100));
      expect(m.revenueLine, '▲ 8% vs 21 Sep');
      expect((m.occupancy, m.occupancyLastMonth), (100, 33)); // 7 of 21
      expect(m.occupancyLine, '▲ 67 pts vs Sep');
    });

    test('the 31st compares with the last day of a shorter month', () {
      final m = thisMonth(
        moves: const [],
        stays: const [],
        activeBeds: 2,
        now: oct(31, 18),
      );
      expect(m.lastMonthPoint, nairobiInstant(2026, 9, 30, 18));
      expect(m.revenueLine, 'Nothing taken by 30 Sep');
      expect((m.occupancy, m.occupancyLastMonth), (0, 0));
      expect(m.occupancyLine, 'Same vs Sep');
    });
  });

  test('a refund awaiting approval reads like the design', () {
    final r = RefundAwaiting(
      refundId: 'r1',
      guestName: 'Peter Kamau',
      roomNumber: '5',
      bedLabel: 'B',
      nights: 3,
      amount: 2100,
      requestedBy: 'Mary Wanjiku',
      requestedAt: oct(21, 9),
    );
    expect(r.subtitle, 'Peter Kamau · Room 5 B · 3 nights');
  });
}
