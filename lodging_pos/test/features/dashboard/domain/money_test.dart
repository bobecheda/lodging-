import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';

import 'dashboard_test.dart' show oct, paid, refunded;

/// The owner's Money screen (Figma "04 Money"): its figures, from the same
/// moves as Today's.
void main() {
  group('weeks', () {
    test('a week starts Monday at Nairobi midnight', () {
      // Wed 21 Oct 2026.
      expect(weekStart(oct(21, 9)), oct(19));
      expect(weekStart(oct(19, 0, 0)), oct(19)); // Monday itself
      expect(weekStart(oct(25, 23, 59)), oct(19)); // Sunday night
      // 00:30 Monday Nairobi is still Sunday in UTC.
      expect(weekStart(oct(26, 0, 30)), oct(26));
      // Across a month: Sun 1 Nov belongs to the week of Mon 26 Oct.
      expect(weekStart(nairobiInstant(2026, 11, 1, 12)), oct(26));
    });

    test('the same moment last week is 7 Nairobi days back', () {
      expect(sameMomentLastWeek(oct(21, 9, 30)), oct(14, 9, 30));
      expect(sameMomentLastWeek(nairobiInstant(2026, 11, 3, 8)), oct(27, 8));
    });
  });

  group('a period’s money', () {
    final now = oct(21, 9, 30); // Wednesday
    final moves = [
      paid(oct(21, 8), 10000), // today
      paid(oct(21, 9), 2000, method: PaymentMethod.paybill),
      paid(oct(21, 9, 10), 700, voided: true), // not counted
      refunded(oct(21, 9, 20), 1400), // paid out today
      refunded(oct(21, 9, 25), 500, voided: true), // voided payout
      paid(oct(21, 10), 9999), // after now
      paid(oct(19, 12), 5000), // Monday: this week
      paid(oct(18, 23, 59), 4000), // Sunday: last week
      paid(oct(14, 9), 3000), // last Wednesday, before 09:30
      paid(oct(14, 9, 45), 800), // last Wednesday, after 09:30
      paid(oct(12, 10), 6000), // last Monday
      paid(oct(1, 7), 20000), // this month
      paid(nairobiInstant(2026, 9, 2, 9), 15000), // September, before 21st
      paid(nairobiInstant(2026, 9, 21, 9, 31), 999), // after the same point
    ];

    test('today: received, refunds paid, net, by method, voids left out, '
        'against the same time last week', () {
      final m = periodMoney(moves, MoneyPeriod.today, now);
      expect(m.received, 12000);
      expect(m.refundsPaid, 1400);
      expect(m.net, 10600);
      expect((m.takings.cash, m.takings.mpesa), (8600, 2000));
      expect(m.voided, 700); // payments voided; voided payouts aren't money
      expect(m.before, 3000);
      expect(m.beforeLabel, 'Same time last Wednesday');
      expect(m.title, 'TODAY SO FAR · NET');
      expect(m.splitTitle, 'CASH VS M-PESA · TODAY');
    });

    test('this week: from Monday, against last week to the same point', () {
      final m = periodMoney(moves, MoneyPeriod.week, now);
      expect(m.received, 17000); // 10,000 + 2,000 + 5,000
      expect(m.net, 15600);
      expect(m.before, 9000); // Mon 12 Oct 6,000 + Wed 14 Oct 3,000
      expect(m.beforeLabel, 'Same point last week');
      expect(m.title, 'THIS WEEK SO FAR · NET');
    });

    test('this month: from the 1st, against the same point last month', () {
      final m = periodMoney(moves, MoneyPeriod.month, now);
      expect(m.received, 17000 + 4000 + 3000 + 800 + 6000 + 20000);
      expect(m.before, 15000);
      expect(m.beforeLabel, 'Same point in September');
      expect(m.title, 'OCTOBER SO FAR · NET');
      expect(m.splitTitle, 'CASH VS M-PESA · OCTOBER');
    });

    test('31 Oct compares with 30 Sep, the last day of a shorter month', () {
      final end = oct(31, 18);
      final m = periodMoney(
        [
          paid(nairobiInstant(2026, 9, 30, 17), 100),
          paid(nairobiInstant(2026, 9, 30, 19), 999), // after 18:00
        ],
        MoneyPeriod.month,
        end,
      );
      expect(m.before, 100);
      expect(m.beforeLabel, 'Same point in September');
    });

    test('a payment at 23:59 is that day’s; at 00:01, the next day’s', () {
      final moves = [paid(oct(20, 23, 59), 1000), paid(oct(21, 0, 1), 2000)];
      expect(periodMoney(moves, MoneyPeriod.today, oct(21, 9)).net, 2000);
      expect(
        periodMoney(
          moves,
          MoneyPeriod.today,
          nairobiInstant(2026, 10, 20, 23, 59, 30),
        ).net,
        1000,
      );
    });

    test('cash and M-Pesa shares, whole percent', () {
      final m = periodMoney(moves, MoneyPeriod.today, now);
      expect((m.cashPercent, m.mpesaPercent), (81, 19));
      final none = periodMoney(const [], MoneyPeriod.today, now);
      expect((none.cashPercent, none.mpesaPercent), (null, null));
    });
  });

  group('daily net, last 14 days', () {
    test('oldest first, today last, voids and payouts counted as on the '
        'desk; the best day and today', () {
      final now = oct(21, 9, 30);
      final days = dailyNet([
        paid(oct(8, 12), 500), // 14 days back: Thu 8 Oct is the first
        paid(oct(7, 12), 9000), // 15 days back: not shown
        paid(oct(20, 10), 26100),
        paid(oct(21, 8), 18400),
        refunded(oct(21, 9), 400),
        paid(oct(21, 9), 300, voided: true),
      ], now);
      expect(days, hasLength(14));
      expect(days.first.day, DateTime.utc(2026, 10, 8));
      expect(days.first.net, 500);
      expect(days.last.day, DateTime.utc(2026, 10, 21));
      expect(days.last.net, 18000);
      expect(days[12].net, 26100);
      final summary = dailySummary(days);
      expect(
        summary,
        'Best day: Tue 20 Oct, KES 26,100. Today so far: KES 18,000.',
      );
      expect(dayLine(days[12]), 'Tue 20 Oct · KES 26,100');
    });

    test('nothing taken: no best day', () {
      final days = dailyNet(const [], oct(21, 9));
      expect(dailySummary(days), 'Nothing taken in the last 14 days.');
    });
  });

  group('nights let, by category', () {
    ChargeNights charge(
      int nights,
      DateTime end, {
      String category = 'Deluxe',
      int price = 700,
    }) => ChargeNights(
      nights: nights,
      periodEnd: end,
      categoryName: category,
      pricePerNight: price,
    );

    test('nights in the period × each stay’s locked price, split by night '
        'across the month; refunded and voided nights out', () {
      final stays = [
        // 29 Sep – 2 Oct: only 1 Oct is in October.
        StayNights(charges: [charge(3, nairobiInstant(2026, 10, 2, 10))]),
        // 18–21 Oct at the locked VIP price, the last night refunded.
        StayNights(
          charges: [charge(3, oct(21, 10), category: 'VIP', price: 1000)],
          refundedNights: 1,
        ),
        // Voided: nothing.
        StayNights(charges: [charge(2, oct(12, 10))], voided: true),
        // An extension at a new price keeps each charge's own price.
        StayNights(
          charges: [charge(1, oct(6, 10)), charge(2, oct(8, 10), price: 750)],
        ),
      ];
      final rows = nightsLetByCategory(
        stays,
        first: DateTime.utc(2026, 10, 1),
        last: DateTime.utc(2026, 10, 21),
      );
      expect(
        [for (final r in rows) (r.name, r.nights, r.value)],
        [('Deluxe', 4, 700 + 700 + 750 + 750), ('VIP', 2, 2000)],
      );
      expect(rows.first.line, '4 bed-nights');
      expect(rows.last.line, '2 bed-nights');
    });

    test('one night reads singular; a period with none is empty', () {
      final rows = nightsLetByCategory(
        [
          StayNights(charges: [charge(1, oct(22, 10))]),
        ],
        first: DateTime.utc(2026, 10, 21),
        last: DateTime.utc(2026, 10, 21),
      );
      expect(rows.single.line, '1 bed-night');
      expect(
        nightsLetByCategory(
          const [],
          first: DateTime.utc(2026, 10, 1),
          last: DateTime.utc(2026, 10, 21),
        ),
        isEmpty,
      );
    });

    test('a period’s dates: today, Monday on, the 1st on', () {
      final now = oct(21, 9);
      expect(periodDates(MoneyPeriod.today, now), (
        first: DateTime.utc(2026, 10, 21),
        last: DateTime.utc(2026, 10, 21),
      ));
      expect(
        periodDates(MoneyPeriod.week, now).first,
        DateTime.utc(2026, 10, 19),
      );
      expect(
        periodDates(MoneyPeriod.month, now).first,
        DateTime.utc(2026, 10, 1),
      );
    });
  });
}
