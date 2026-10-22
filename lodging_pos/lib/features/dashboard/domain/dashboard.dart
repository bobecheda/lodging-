/// The owner's Today (desk now, phone in sprint 2): the four cards' figures.
/// Pure Dart, so the phone app reuses them. Days are Nairobi calendar days,
/// midnight to midnight; money is whole KES.
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../payments/domain/payment_rules.dart';
import '../../price_requests/domain/price_request.dart';

// ── Days ─────────────────────────────────────────────────────────────────

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', //
  'Saturday', 'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Nairobi midnight starting the day of [utc] (as UTC).
DateTime dayStart(DateTime utc) {
  final t = toNairobi(utc);
  return nairobiInstant(t.year, t.month, t.day);
}

/// Nairobi midnight starting the 1st of [utc]'s month (as UTC).
DateTime monthStart(DateTime utc) {
  final t = toNairobi(utc);
  return nairobiInstant(t.year, t.month, 1);
}

/// The same wall-clock moment one month before [utc], on the same day of
/// the month, or the last day of a shorter month (31 Oct → 30 Sep).
DateTime sameMomentLastMonth(DateTime utc) {
  final t = toNairobi(utc);
  final lastDay = DateTime.utc(t.year, t.month, 0).day; // of the month before
  final day = t.day < lastDay ? t.day : lastDay;
  return nairobiInstant(t.year, t.month - 1, day, t.hour, t.minute, t.second);
}

/// "Wednesday 21 October": Today's date line.
String formatLongDate(DateTime utc) {
  final t = toNairobi(utc);
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}

/// "OCTOBER": the This month card's heading.
String monthName(DateTime utc) =>
    _months[toNairobi(utc).month - 1].toUpperCase();

// ── Money ────────────────────────────────────────────────────────────────

/// A payment received, or a refund paid out, for the money cards.
final class MoneyMove {
  const MoneyMove({
    required this.at,
    required this.amount,
    required this.method,
    required this.isPayout,
    this.voided = false,
  });

  /// UTC: when the payment was received, or the refund paid out.
  final DateTime at;

  /// Whole KES, always positive; a payout counts against the takings.
  final int amount;
  final PaymentMethod method;
  final bool isPayout;

  /// Voided payments and payouts don't count (BR-11).
  final bool voided;
}

/// Net takings, by method: payments − refunds paid − anything voided.
final class Takings {
  const Takings({required this.cash, required this.mpesa});

  final int cash;
  final int mpesa;
  int get net => cash + mpesa;
}

/// Net takings of [moves] at or after [from] and before [to].
Takings takingsBetween(
  Iterable<MoneyMove> moves, {
  required DateTime from,
  required DateTime to,
}) {
  var cash = 0;
  var mpesa = 0;
  for (final m in moves) {
    if (m.voided || m.at.isBefore(from) || !m.at.isBefore(to)) continue;
    final signed = m.isPayout ? -m.amount : m.amount;
    switch (m.method) {
      case PaymentMethod.cash:
        cash += signed;
      case PaymentMethod.paybill:
        mpesa += signed;
    }
  }
  return Takings(cash: cash, mpesa: mpesa);
}

/// Today's money: today so far, against the same weekday last week up to
/// the same time (a half day compared with a whole day misleads).
final class TodaysMoney {
  const TodaysMoney({required this.today, required this.lastWeek});

  final Takings today;

  /// Net, same weekday last week, midnight to this time of day.
  final int lastWeek;
}

TodaysMoney todaysMoney(Iterable<MoneyMove> moves, DateTime now) {
  final weekAgo = addNairobiDays(now, -7);
  return TodaysMoney(
    today: takingsBetween(moves, from: dayStart(now), to: now),
    lastWeek: takingsBetween(moves, from: dayStart(weekAgo), to: weekAgo).net,
  );
}

/// "▲ 12% vs last Wednesday (KES 16,400)". The arrow is never coloured.
String vsLastWeekLine(TodaysMoney money, DateTime now) {
  final day = 'last ${_weekdays[toNairobi(now).weekday - 1]}';
  final before = money.lastWeek;
  final change = _percentChange(money.today.net, before);
  if (change == null) return 'Nothing taken by now $day';
  return '${_arrowed(change, '%')} vs $day (${formatKes(before)})';
}

/// "▲ 8% vs 21 Sep": This month's revenue line.
String vsLastMonthRevenueLine(int now, int before, DateTime lastMonthPoint) {
  final t = toNairobi(lastMonthPoint);
  final when = '${t.day} ${_monthsShort[t.month - 1]}';
  final change = _percentChange(now, before);
  if (change == null) return 'Nothing taken by $when';
  return '${_arrowed(change, '%')} vs $when';
}

/// Whole-percent change, or null when there is nothing to compare with.
int? _percentChange(int now, int before) {
  if (before <= 0) return null;
  return ((now - before) * 100 / before).round();
}

String _arrowed(int change, String unit) => switch (change) {
  0 => 'Same',
  > 0 => '▲ $change$unit',
  _ => '▼ ${-change}$unit',
};

// ── Beds ─────────────────────────────────────────────────────────────────

/// Beds right now, from the bed board's statuses (open rooms' active beds).
final class BedsNow {
  const BedsNow({
    required this.occupied,
    required this.overstay,
    required this.toClean,
    required this.ready,
  });

  factory BedsNow.fromCounts(Map<BoardStatus, int> counts) => BedsNow(
    occupied: counts[BoardStatus.occupied] ?? 0,
    overstay: counts[BoardStatus.overstay] ?? 0,
    toClean: counts[BoardStatus.toClean] ?? 0,
    ready: counts[BoardStatus.ready] ?? 0,
  );

  final int occupied;
  final int overstay;
  final int toClean;
  final int ready;

  int get total => occupied + overstay + toClean + ready;

  /// A guest is in the bed: occupied or overstaying.
  int get inUse => occupied + overstay;

  /// Whole percent of beds in use; null with no beds.
  int? get percentInUse => total == 0 ? null : (inUse * 100 / total).round();
}

// ── Occupancy ────────────────────────────────────────────────────────────

/// One stay's nights for occupancy: its charges, whether it was voided, and
/// how many nights a refund took back (unless the refund was rejected).
final class StayNights {
  const StayNights({
    required this.charges,
    this.voided = false,
    this.refundedNights = 0,
  });

  final List<ChargeNights> charges;
  final bool voided;

  /// The stay's last nights, not used (BR-8); not sold.
  final int refundedNights;
}

/// A charge's nights: [nights] ending at [periodEnd] (10:00).
final class ChargeNights {
  const ChargeNights({required this.nights, required this.periodEnd});
  final int nights;
  final DateTime periodEnd;
}

/// The Nairobi date each of the stay's sold nights belongs to: a night
/// ending at 10:00 on Friday is Thursday's night. The refunded nights (the
/// last ones) are left out; a voided stay has none.
List<DateTime> soldNightDates(StayNights stay) {
  if (stay.voided) return const [];
  final dates = <DateTime>[];
  for (final c in stay.charges) {
    final end = toNairobi(c.periodEnd);
    for (var i = c.nights; i >= 1; i--) {
      dates.add(DateTime.utc(end.year, end.month, end.day - i));
    }
  }
  dates.sort();
  final keep = dates.length - stay.refundedNights;
  return dates.sublist(0, keep < 0 ? 0 : keep);
}

/// Bed-nights sold on the Nairobi dates [first] to [last] (inclusive; both
/// as returned by [nairobiDate]).
int bedNightsSold(
  Iterable<StayNights> stays, {
  required DateTime first,
  required DateTime last,
}) {
  var sold = 0;
  for (final stay in stays) {
    for (final d in soldNightDates(stay)) {
      if (!d.isBefore(first) && !d.isAfter(last)) sold++;
    }
  }
  return sold;
}

/// The Nairobi date of [utc], as a UTC midnight to compare by.
DateTime nairobiDate(DateTime utc) {
  final t = toNairobi(utc);
  return DateTime.utc(t.year, t.month, t.day);
}

/// Occupancy: bed-nights sold ÷ active bed-nights, as a whole percent, or
/// null with no beds. Active bed-nights are today's active beds × [nights]
/// (bed open/close history isn't kept yet).
int? occupancyPercent({
  required int sold,
  required int activeBeds,
  required int nights,
}) {
  final available = activeBeds * nights;
  if (available <= 0) return null;
  return (sold * 100 / available).round();
}

// ── This month ───────────────────────────────────────────────────────────

/// This month so far against the same point last month.
final class ThisMonth {
  const ThisMonth({
    required this.revenue,
    required this.revenueLastMonth,
    required this.lastMonthPoint,
    required this.occupancy,
    required this.occupancyLastMonth,
  });

  final int revenue;
  final int revenueLastMonth;

  /// The moment last month the figures are compared at.
  final DateTime lastMonthPoint;
  final int? occupancy;
  final int? occupancyLastMonth;

  String get revenueLine =>
      vsLastMonthRevenueLine(revenue, revenueLastMonth, lastMonthPoint);

  /// "▼ 3 pts vs Sep".
  String get occupancyLine {
    final month = _monthsShort[toNairobi(lastMonthPoint).month - 1];
    final now = occupancy;
    final before = occupancyLastMonth;
    if (now == null || before == null) return 'No beds to compare';
    return '${_arrowed(now - before, ' pts')} vs $month';
  }
}

/// This month's figures at [now]: net revenue from the 1st to now, and
/// occupancy over the nights from the 1st to today; last month the same,
/// up to [sameMomentLastMonth].
ThisMonth thisMonth({
  required Iterable<MoneyMove> moves,
  required Iterable<StayNights> stays,
  required int activeBeds,
  required DateTime now,
}) {
  final then = sameMomentLastMonth(now);
  int occupancyFor(DateTime at) {
    final first = nairobiDate(monthStart(at));
    final last = nairobiDate(at);
    final nights = last.difference(first).inDays + 1;
    return occupancyPercent(
          sold: bedNightsSold(stays, first: first, last: last),
          activeBeds: activeBeds,
          nights: nights,
        ) ??
        -1;
  }

  final occupancy = occupancyFor(now);
  final occupancyBefore = occupancyFor(then);
  return ThisMonth(
    revenue: takingsBetween(moves, from: monthStart(now), to: now).net,
    revenueLastMonth: takingsBetween(
      moves,
      from: monthStart(then),
      to: then,
    ).net,
    lastMonthPoint: then,
    occupancy: occupancy < 0 ? null : occupancy,
    occupancyLastMonth: occupancyBefore < 0 ? null : occupancyBefore,
  );
}

// ── Needs your attention ─────────────────────────────────────────────────

/// A refund waiting for the owner's decision (BR-8a).
final class RefundAwaiting {
  const RefundAwaiting({
    required this.refundId,
    required this.guestName,
    required this.roomNumber,
    required this.bedLabel,
    required this.nights,
    required this.amount,
    required this.requestedBy,
    required this.requestedAt,
  });

  final String refundId;
  final String guestName;
  final String roomNumber;
  final String bedLabel;
  final int nights;
  final int amount;

  /// The requester's name.
  final String requestedBy;

  /// UTC.
  final DateTime requestedAt;

  /// "Peter Kamau · Room 5 B · 3 nights".
  String get subtitle =>
      '$guestName · Room $roomNumber $bedLabel · '
      '$nights ${nights == 1 ? 'night' : 'nights'}';
}

/// A price change the supervisor asked for, waiting for the owner (BR-2).
final class PriceAwaiting {
  const PriceAwaiting({
    required this.requestId,
    required this.categoryName,
    required this.oldPrice,
    required this.newPrice,
    required this.requestedBy,
    required this.requestedByRole,
    required this.requestedAt,
  });

  final String requestId;
  final String categoryName;
  final int oldPrice;
  final int newPrice;

  /// The requester's full name.
  final String requestedBy;

  /// As stored: `supervisor`.
  final String requestedByRole;

  /// UTC.
  final DateTime requestedAt;

  /// "Deluxe: 700 → 750".
  String get title =>
      '$categoryName: ${formatKesPlain(oldPrice)} → '
      '${formatKesPlain(newPrice)}';

  /// "From Grace (supervisor) · today 09:15", as seen at [now].
  String subtitle(DateTime now) =>
      'From ${requestedBy.split(' ').first} ($requestedByRole) · '
      '${formatWhen(requestedAt, now: now)}';

  /// "+50": the change a night.
  String get change => formatPriceChange(newPrice - oldPrice);
}
