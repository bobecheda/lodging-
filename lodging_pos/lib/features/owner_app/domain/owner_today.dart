/// What the owner's phone shows on Today besides the desk's cards: the
/// desk's line, when the figures were loaded, and the shift shortages and
/// voided payments that need the owner. Pure Dart.
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../price_requests/domain/price_request.dart';
import '../../setup/domain/bed_category.dart';

// ── The desk ─────────────────────────────────────────────────────────────

/// A desk's last heartbeat (`desk_status`, every 5 minutes).
final class DeskStatus {
  const DeskStatus({
    required this.deviceId,
    required this.reportedAt,
    required this.pending,
    this.lastPushAt,
    this.problem,
  });

  final String deviceId;

  /// UTC.
  final DateTime reportedAt;

  /// When the desk last sent its changes (UTC); null before its first.
  final DateTime? lastPushAt;

  /// Changes waiting to go up.
  final int pending;
  final String? problem;
}

/// The header's line about the desk.
final class DeskLine {
  const DeskLine(this.text, {required this.online});
  final String text;
  final bool online;
}

/// Heard from within this long: online (two heartbeats may be missed).
const deskOnlineWithin = Duration(minutes: 11);

/// "Desk online · up to date", "Desk online · 3 changes waiting", "Desk
/// online · sync problem" or "Desk offline · last seen today 09:18", for the
/// desk heard from last.
DeskLine deskLine(List<DeskStatus> desks, DateTime now) {
  if (desks.isEmpty) {
    return const DeskLine(
      'The desk isn’t connected to the cloud yet.',
      online: false,
    );
  }
  final d = desks.reduce((a, b) => b.reportedAt.isAfter(a.reportedAt) ? b : a);
  if (now.difference(d.reportedAt) > deskOnlineWithin) {
    return DeskLine(
      'Desk offline · last seen ${formatWhen(d.reportedAt, now: now)}',
      online: false,
    );
  }
  final state = switch (d) {
    DeskStatus(problem: _?) => 'sync problem',
    DeskStatus(pending: 0) => 'up to date',
    DeskStatus(pending: 1) => '1 change waiting',
    DeskStatus(:final pending) => '$pending changes waiting',
  };
  return DeskLine('Desk online · $state', online: true);
}

/// How fresh the cloud's figures are (Money, Figma "04"): "Up to the desk's
/// last sync, 14:05", "· 3 changes not sent yet" while some wait.
String freshnessLine(List<DeskStatus> desks, DateTime now) {
  if (desks.isEmpty) return 'The desk isn’t connected to the cloud yet.';
  final d = desks.reduce((a, b) => b.reportedAt.isAfter(a.reportedAt) ? b : a);
  final pushed = d.lastPushAt;
  if (pushed == null) return 'The desk hasn’t synced yet.';
  final at = _sameDay(pushed, now)
      ? formatTime(pushed)
      : formatWhen(pushed, now: now);
  final waiting = switch (d.pending) {
    0 => '',
    1 => ' · 1 change not sent yet',
    final n => ' · $n changes not sent yet',
  };
  return 'Up to the desk’s last sync, $at$waiting.';
}

bool _sameDay(DateTime a, DateTime b) {
  final x = toNairobi(a);
  final y = toNairobi(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// "Updated just now", "Updated 4 min ago", "Updated today 09:15"; offline,
/// "Offline · showing today 09:15" (the last figures loaded).
String updatedLine(DateTime loadedAt, DateTime now, {required bool offline}) {
  if (offline) return 'Offline · showing ${formatWhen(loadedAt, now: now)}';
  final minutes = now.difference(loadedAt).inMinutes;
  if (minutes < 1) return 'Updated just now';
  if (minutes < 60) return 'Updated $minutes min ago';
  return 'Updated ${formatWhen(loadedAt, now: now)}';
}

// ── Needs your attention ─────────────────────────────────────────────────

/// How far back shortages and voids are shown.
DateTime attentionSince(DateTime now) => now.subtract(const Duration(days: 7));

String _firstName(String fullName) => fullName.split(' ').first;

/// A closed shift, as Today reads it.
final class ClosedShift {
  const ClosedShift({
    required this.shiftId,
    required this.userName,
    required this.closedAt,
    required this.variance,
  });

  final String shiftId;
  final String userName;

  /// UTC.
  final DateTime closedAt;

  /// Counted − expected cash; negative when short.
  final int variance;

  String get title => 'Cash short at shift close';

  /// "John · today 08:30".
  String subtitle(DateTime now) =>
      '${_firstName(userName)} · ${formatWhen(closedAt, now: now)}';

  /// "KES 300": how much was short.
  String get figure => formatKes(-variance);
}

/// Shifts closed short since [attentionSince], oldest first.
List<ClosedShift> shortages(Iterable<ClosedShift> closed, DateTime now) {
  final since = attentionSince(now);
  return [
    for (final s in closed)
      if (s.variance < 0 && !s.closedAt.isBefore(since)) s,
  ]..sort((a, b) => a.closedAt.compareTo(b.closedAt));
}

/// A payment voided (BR-11), shown for [attentionSince].
final class PaymentVoided {
  const PaymentVoided({
    required this.voidId,
    required this.receiptNumber,
    required this.amount,
    required this.reason,
    required this.voidedBy,
    required this.voidedAt,
  });

  final String voidId;
  final String receiptNumber;
  final int amount;
  final String reason;

  /// The full name of who voided it.
  final String voidedBy;

  /// UTC.
  final DateTime voidedAt;

  String get title => 'Payment voided · $receiptNumber';

  /// "Wrong bed · by Grace · yesterday 18:40".
  String subtitle(DateTime now) =>
      '$reason · by ${_firstName(voidedBy)} · '
      '${formatWhen(voidedAt, now: now)}';

  String get figure => formatKes(amount);
}

// ── Prices ───────────────────────────────────────────────────────────────

/// A category on the owner's Prices (Figma "06 Prices"), with its active
/// beds ("8 beds").
final class OwnerCategory {
  const OwnerCategory(this.category, {required this.beds});
  final BedCategory category;
  final int beds;

  String get bedsLine => beds == 1 ? '1 bed' : '$beds beds';
}

/// A price request waiting for the owner, with what the card shows.
final class OwnerPriceRequest {
  const OwnerPriceRequest({
    required this.request,
    required this.category,
    required this.requestedByName,
    required this.requestedByRole,
  });

  final PriceRequest request;

  /// The category as it is now.
  final BedCategory category;
  final String requestedByName;

  /// As stored: `supervisor`.
  final String requestedByRole;

  String get id => request.id;

  /// The price has moved on since the request: it can only be rejected
  /// ([staleError]).
  String? get staleMessage => staleError(request, category);

  /// "REQUEST FROM GRACE (SUPERVISOR)".
  String get heading =>
      'REQUEST FROM ${requestedByName.split(' ').first.toUpperCase()} '
      '(${requestedByRole.toUpperCase()})';

  /// "“Other lodgings nearby charge 800.” · today 09:15".
  String reasonLine(DateTime now) {
    final when = formatWhen(request.requestedAt, now: now);
    final reason = request.reason;
    return reason == null ? 'Asked $when' : '“$reason” · $when';
  }
}

// ── Everything Today shows ───────────────────────────────────────────────

/// One load of the owner's Today. Kept in memory only.
final class OwnerToday {
  const OwnerToday({
    required this.lodgingName,
    required this.desks,
    required this.moves,
    required this.stays,
    required this.refunds,
    required this.prices,
    required this.shortages,
    required this.voids,
    required this.rooms,
    required this.graceMinutes,
    this.categories = const [],
    this.priceRequests = const [],
  });

  final String lodgingName;
  final List<DeskStatus> desks;
  final List<MoneyMove> moves;
  final List<StayNights> stays;
  final List<RefundAwaiting> refunds;
  final List<PriceAwaiting> prices;

  /// Oldest first.
  final List<ClosedShift> shortages;

  /// Oldest first.
  final List<PaymentVoided> voids;

  /// Active rooms and beds with their active stays (no guest names: the
  /// counts don't need them).
  final List<BoardRoom> rooms;
  final int graceMinutes;

  /// Every category in sort order, closed ones included (Prices).
  final List<OwnerCategory> categories;

  /// Price requests waiting for the owner, oldest first (Prices).
  final List<OwnerPriceRequest> priceRequests;
}
