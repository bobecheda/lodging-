/// What the v2 check-in screen (PR 6) says: the bed row, the bed chooser,
/// the summary lines and the confirm line. Pure Dart; the rules themselves
/// stay in `check_in.dart`.
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';
import '../../setup/domain/rooms.dart';
import 'check_in.dart';

/// `104 A`.
String bedName(String roomNumber, BedLabel label) =>
    '$roomNumber ${label.code}';

/// `104 A`, or `107 A + 107 B` for the whole room.
String bedRowTitle(String roomNumber, List<BedSummary> beds) =>
    beds.map((b) => bedName(roomNumber, b.label)).join(' + ');

/// Under the title: `Comfort · KES 600 a night · cleaned 08:15 · Mary` for
/// one bed ([cleaned] from `cleanedLine`, if it was cleaned through the
/// desk); for the whole room `Normal · KES 500 a night each`, or
/// `KES 700 + KES 600 a night` when the beds' prices differ.
String bedRowMeta(List<BedSummary> beds, {String? cleaned}) {
  if (beds.length == 1) {
    final b = beds.single;
    return [
      '${b.categoryName} · ${formatKes(b.pricePerNight)} a night',
      if (cleaned != null && cleaned.isNotEmpty)
        '${cleaned[0].toLowerCase()}${cleaned.substring(1)}',
    ].join(' · ');
  }
  final prices = {for (final b in beds) b.pricePerNight};
  if (prices.length > 1) {
    return '${beds.map((b) => formatKes(b.pricePerNight)).join(' + ')} '
        'a night';
  }
  final names = [for (final n in beds.map((b) => b.categoryName).toSet()) n]
      .join(' + ');
  return '$names · ${formatKes(prices.single)} a night each';
}

/// Beside the whole-room switch when the room's other bed can't be let:
/// `104 B has a guest`; null when it can.
String? wholeRoomNote(String roomNumber, BedSummary other) {
  final reason = letReason(other, checkInOccupancy(other));
  return reason == null ? null : '${bedName(roomNumber, other.label)} $reason';
}

/// A bed in the chooser.
final class ReadyBed {
  const ReadyBed({required this.room, required this.bed});

  final RoomSummary room;
  final BedSummary bed;

  String get name => bedName(room.number, bed.label);
}

/// One category in the chooser: its name, colour and price, then its beds.
final class ReadyBedGroup {
  const ReadyBedGroup({
    required this.categoryName,
    required this.colour,
    required this.pricePerNight,
    required this.beds,
  });

  final String categoryName;
  final String colour;
  final int pricePerNight;
  final List<ReadyBed> beds;
}

/// The beds a check-in may take (BR-5: active, Available and clean),
/// grouped by category, the dearest first, each in [rooms]' order.
List<ReadyBedGroup> readyBedGroups(List<RoomSummary> rooms) {
  final byCategory = <String, List<ReadyBed>>{};
  for (final r in rooms) {
    for (final b in r.beds) {
      if (letBlocker(b, checkInOccupancy(b)) != null) continue;
      byCategory
          .putIfAbsent(b.categoryId, () => [])
          .add(ReadyBed(room: r, bed: b));
    }
  }
  final groups = [
    for (final beds in byCategory.values)
      ReadyBedGroup(
        categoryName: beds.first.bed.categoryName,
        colour: beds.first.bed.categoryColour,
        pricePerNight: beds.first.bed.pricePerNight,
        beds: List.unmodifiable(beds),
      ),
  ];
  groups.sort((a, b) {
    final byPrice = b.pricePerNight.compareTo(a.pricePerNight);
    return byPrice != 0 ? byPrice : a.categoryName.compareTo(b.categoryName);
  });
  return groups;
}

/// "Ready beds · 6".
int readyBedCount(List<ReadyBedGroup> groups) =>
    groups.fold(0, (n, g) => n + g.beds.length);

String _nights(int n) => n == 1 ? '1 night' : '$n nights';

/// Under the total: `2 nights × KES 600`; the whole room at one price
/// `2 beds × 2 nights × KES 500 · one receipt`; at two prices a line per
/// bed, the last ending `· one receipt`. [beds] are (name, price).
List<String> checkInPriceLines({
  required int nights,
  required List<(String, int)> beds,
}) {
  if (beds.length == 1) {
    return ['${_nights(nights)} × ${formatKes(beds.single.$2)}'];
  }
  final prices = {for (final (_, p) in beds) p};
  if (prices.length == 1) {
    return [
      '${beds.length} beds × ${_nights(nights)} × '
          '${formatKes(prices.single)} · one receipt',
    ];
  }
  return [
    for (final (i, (name, price)) in beds.indexed)
      '$name · ${_nights(nights)} × ${formatKes(price)}'
          '${i == beds.length - 1 ? ' · one receipt' : ''}',
  ];
}

/// How far the guest is: none yet, a new guest still missing their name or
/// phone, or chosen (a guest found, or a new one with name and phone).
enum GuestReadiness { none, incomplete, ready }

/// The line above "Save and print receipt".
final class CheckInConfirm {
  const CheckInConfirm._(this.text, {required this.ready});

  final String text;

  /// False: grey, naming the first thing still missing.
  final bool ready;
}

/// `M-Pesa · KES 1,200 · out Fri 10:00` (the whole room adds `· 2 beds`)
/// once everything is chosen; until then the first thing missing: the bed,
/// the nights, the guest, then the method.
CheckInConfirm checkInConfirm({
  required CheckInQuote? quote,
  required bool bedChosen,
  required String? nightsProblem,
  required GuestReadiness guest,
  required PaymentMethod? method,
}) {
  CheckInConfirm missing(String text) => CheckInConfirm._(text, ready: false);
  if (!bedChosen) return missing('Choose a bed');
  if (nightsProblem != null) return missing(nightsProblem);
  if (quote == null) return missing('Choose a bed');
  switch (guest) {
    case GuestReadiness.none:
      return missing('Find or add the guest');
    case GuestReadiness.incomplete:
      return missing('Add the new guest’s name and phone');
    case GuestReadiness.ready:
  }
  if (method == null) return missing('Choose Cash or M-Pesa');
  final beds = quote.beds.length;
  return CheckInConfirm._(
    [
      method.label,
      formatKes(quote.total),
      if (beds > 1) '$beds beds',
      'out ${formatWeekday(quote.paidUntil)} ${formatTime(quote.paidUntil)}',
    ].join(' · '),
    ready: true,
  );
}

/// On the selected guest's row: `3 stays`.
String stayCountLabel(int stays) => switch (stays) {
  0 => 'No stays yet',
  1 => '1 stay',
  _ => '$stays stays',
};
