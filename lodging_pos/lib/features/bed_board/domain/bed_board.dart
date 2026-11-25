/// The bed board (FD-2): each bed's status, derived from its active stay,
/// the clock and its cleanliness. Never stored. Pure Dart.
library;

import '../../../core/category_colour_keys.dart';
import '../../../core/clock/nairobi.dart';
import '../../setup/domain/rooms.dart';
import '../../stays/domain/stay_rules.dart';

/// One per bed, never overlapping: Overstay > In use > To clean > Ready.
enum BoardStatus {
  ready('Ready'),
  occupied('Occupied'),
  overstay('Overstay'),
  toClean('Needs cleaning');

  const BoardStatus(this.label);

  /// As the desk's board and the owner's Beds name it.
  final String label;
}

/// The active stay on a bed, as the board shows it.
final class BoardStay {
  const BoardStay({
    required this.stayId,
    required this.guestName,
    required this.guestPhone,
    required this.paidUntil,
  });

  final String stayId;
  final String guestName;
  final String guestPhone;

  /// UTC.
  final DateTime paidUntil;
}

/// An active bed in an open room.
final class BoardBed {
  const BoardBed({
    required this.id,
    required this.label,
    required this.categoryId,
    required this.categoryName,
    required this.pricePerNight,
    required this.cleanliness,
    required this.stay,
    this.cleaner,
    this.categoryColour = defaultCategoryColour,
  });

  final String id;
  final BedLabel label;
  final String categoryId;
  final String categoryName;

  /// The category's colour key (v2 PR 4) for the room card's stripe.
  final String categoryColour;

  /// The category's current price, whole KES.
  final int pricePerNight;
  final Cleanliness cleanliness;
  final BoardStay? stay;

  /// Who has this bed to clean (an open task, FD-9), by display name; null
  /// when nobody has it.
  final String? cleaner;
}

/// An open room and its active beds (A, B). Closed rooms and inactive beds
/// aren't on the board.
final class BoardRoom {
  const BoardRoom({required this.id, required this.number, required this.beds});

  final String id;
  final String number;
  final List<BoardBed> beds;
}

BoardStatus statusOf(
  BoardBed bed, {
  required DateTime now,
  required int graceMinutes,
}) {
  switch (occupancyAt(
    paidUntil: bed.stay?.paidUntil,
    now: now,
    graceMinutes: graceMinutes,
  )) {
    case Occupancy.overstay:
      return BoardStatus.overstay;
    case Occupancy.occupied:
      return BoardStatus.occupied;
    case Occupancy.available:
      return bed.cleanliness == Cleanliness.notCleaned
          ? BoardStatus.toClean
          : BoardStatus.ready;
  }
}

/// What the board is narrowed to. Null [status] or [categoryId] is "all".
final class BoardFilter {
  const BoardFilter({this.status, this.categoryId});

  final BoardStatus? status;
  final String? categoryId;
}

/// One overstaying bed, for the alert bar.
final class OverstayAlert {
  const OverstayAlert({
    required this.stayId,
    required this.roomNumber,
    required this.label,
    required this.guestName,
    required this.paidUntil,
    required this.graceEnded,
  });

  final String stayId;
  final String roomNumber;
  final BedLabel label;
  final String guestName;
  final DateTime paidUntil;
  final DateTime graceEnded;
}

/// "1 overstay", "3 overstays": the owner's alert heading.
String overstayCount(int n) => n == 1 ? '1 overstay' : '$n overstays';

/// The owner's alert line (Figma "05 Beds"): where, and how long past the
/// grace period; never who. "Room 5 B · paid to 10:00, now 40 min past the
/// grace period."
String overstayLine(OverstayAlert a, {required DateTime now}) {
  final sameDay = _nairobiDate(a.paidUntil) == _nairobiDate(now);
  final paidTo = sameDay
      ? formatTime(a.paidUntil)
      : formatWhen(a.paidUntil, now: now);
  return 'Room ${a.roomNumber} ${a.label.code} · paid to $paidTo, now '
      '${formatOverdue(now.difference(a.graceEnded))} past the grace period.';
}

DateTime _nairobiDate(DateTime utc) {
  final t = toNairobi(utc);
  return DateTime.utc(t.year, t.month, t.day);
}

/// "40 min", "2 h 15 min", "1 day", "2 days 3 h"; "under a minute".
String formatOverdue(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return '${d.inHours} h${m == 0 ? '' : ' $m min'}';
  }
  final days = d.inDays;
  final h = d.inHours % 24;
  return '$days ${days == 1 ? 'day' : 'days'}${h == 0 ? '' : ' $h h'}';
}

// ── The v2 board's words (PR 5, Figma "Desk · Bed board") ─────────────

/// The guest's surname as the tiles show it: the last word of the name.
String shortGuestName(String fullName) {
  final words = fullName.trim().split(RegExp(r'\s+'));
  return words.last;
}

/// "45 min", "2 h", "1 d": how long past, in its largest whole unit.
String compactOverdue(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes < 0 ? 0 : d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return '${d.inDays} d';
}

/// A tile's one line: "Ready"; "Otieno · Thu" (paid until Thursday) or
/// "Kamau · 11:30" (due out today); "Kamau · 2 h" (past checkout);
/// "To clean" or "To clean · Mary" (who has it).
String tileLine(BoardBed bed, BoardStatus status, {required DateTime now}) {
  final stay = bed.stay;
  return switch (status) {
    BoardStatus.ready => 'Ready',
    BoardStatus.toClean =>
      bed.cleaner == null ? 'To clean' : 'To clean · ${bed.cleaner}',
    BoardStatus.occupied =>
      '${shortGuestName(stay!.guestName)} · '
          '${_sameNairobiDay(stay.paidUntil, now) ? formatTime(stay.paidUntil) : formatWeekday(stay.paidUntil)}',
    BoardStatus.overstay =>
      '${shortGuestName(stay!.guestName)} · '
          '${compactOverdue(now.difference(stay.paidUntil))}',
  };
}

bool _sameNairobiDay(DateTime a, DateTime b) =>
    _nairobiDate(a) == _nairobiDate(b);

/// The overstay card's line: "104 B · Kamau".
String overstayWho(OverstayAlert a) =>
    '${a.roomNumber} ${a.label.code} · ${shortGuestName(a.guestName)}';

/// The overstay card's second line: "2 h past 10:00" (since checkout).
String overstayPast(OverstayAlert a, {required DateTime now}) =>
    '${compactOverdue(now.difference(a.paidUntil))} past '
    '${formatTime(a.paidUntil)}';

/// How long an overstay has run, for the Now strip's rows: "40 min",
/// "2 h" under a day, then "1 day", "32 days".
String overstayLength(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes < 0 ? 0 : d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return d.inDays == 1 ? '1 day' : '${d.inDays} days';
}

/// The Overstay card shows at most 3 rows, the oldest first; with [more]
/// above 0 its title line offers "Show all".
({int shown, int more}) nowRows(int count, {int max = 3}) =>
    count <= max ? (shown: count, more: 0) : (shown: max, more: count - max);

/// How many chips of [widths] the To clean card shows in [lines] lines of
/// [maxWidth] (chips [gap] apart, wrapping left to right): all of them when
/// they fit, else as many as fit with the "+ N more" chip
/// ([moreWidth] of N) after them on the last line.
int chipsThatFit({
  required List<double> widths,
  required double maxWidth,
  required double gap,
  required int lines,
  required double Function(int more) moreWidth,
}) {
  bool fits(List<double> chips) {
    var line = 1;
    var x = 0.0;
    for (final w in chips) {
      if (x > 0 && x + gap + w > maxWidth) {
        line++;
        x = 0;
      }
      x += (x > 0 ? gap : 0) + w;
      if (line > lines) return false;
    }
    return true;
  }

  if (fits(widths)) return widths.length;
  for (var n = widths.length - 1; n >= 0; n--) {
    if (fits([...widths.take(n), moreWidth(widths.length - n)])) return n;
  }
  return 0;
}

/// A room's categories for its card, each once in bed order: (name,
/// colour key). One for most rooms; two when its beds differ.
List<(String, String)> roomCategories(BoardRoom room) {
  final seen = <String>{};
  return [
    for (final b in room.beds)
      if (seen.add(b.categoryId)) (b.categoryName, b.categoryColour),
  ];
}

/// The board after filtering, with counts for the chips and the overstays
/// for the alert bar.
final class BoardView {
  const BoardView({
    required this.rooms,
    required this.counts,
    required this.overstays,
  });

  /// Rooms in natural order; with a status filter or search, only rooms with
  /// a matching bed, and only those beds.
  final List<BoardRoom> rooms;

  /// Beds per status after the category filter and search (not the status
  /// filter, so every chip keeps its number).
  final Map<BoardStatus, int> counts;

  /// Every overstay on the board, oldest paid_until first, whatever the
  /// filter.
  final List<OverstayAlert> overstays;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

BoardView boardView(
  List<BoardRoom> rooms,
  BoardFilter filter, {
  required DateTime now,
  required int graceMinutes,
}) {
  BoardStatus status(BoardBed b) =>
      statusOf(b, now: now, graceMinutes: graceMinutes);
  final sorted = [...rooms]
    ..sort((a, b) => compareRoomNumbers(a.number, b.number));

  final counts = {for (final s in BoardStatus.values) s: 0};
  final overstays = <OverstayAlert>[];
  final shown = <BoardRoom>[];
  for (final room in sorted) {
    final beds = <BoardBed>[];
    for (final bed in room.beds) {
      final s = status(bed);
      if (s == BoardStatus.overstay) {
        overstays.add(
          OverstayAlert(
            stayId: bed.stay!.stayId,
            roomNumber: room.number,
            label: bed.label,
            guestName: bed.stay!.guestName,
            paidUntil: bed.stay!.paidUntil,
            graceEnded: bed.stay!.paidUntil.add(
              Duration(minutes: graceMinutes),
            ),
          ),
        );
      }
      if (filter.categoryId != null && bed.categoryId != filter.categoryId) {
        continue;
      }
      counts[s] = counts[s]! + 1;
      if (filter.status == null || filter.status == s) beds.add(bed);
    }
    final narrowed = filter.status != null || filter.categoryId != null;
    if (beds.isNotEmpty || (!narrowed && room.beds.isEmpty)) {
      shown.add(BoardRoom(id: room.id, number: room.number, beds: beds));
    }
  }
  overstays.sort((a, b) => a.paidUntil.compareTo(b.paidUntil));
  return BoardView(rooms: shown, counts: counts, overstays: overstays);
}

/// The search box: a room number (exact), part of the occupant's name, or
/// the start of their phone in any common form.
