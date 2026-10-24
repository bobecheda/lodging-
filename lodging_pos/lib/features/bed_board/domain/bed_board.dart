/// The bed board (FD-2): each bed's status, derived from its active stay,
/// the clock and its cleanliness. Never stored. Pure Dart.
library;

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
  });

  final String id;
  final BedLabel label;
  final String categoryId;
  final String categoryName;

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
  const BoardFilter({this.status, this.categoryId, this.query = ''});

  final BoardStatus? status;
  final String? categoryId;

  /// Room number, or the current occupant's name or phone.
  final String query;
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
  final query = _Query.parse(filter.query);
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
      if (!query.matches(room, bed)) continue;
      counts[s] = counts[s]! + 1;
      if (filter.status == null || filter.status == s) beds.add(bed);
    }
    final narrowed =
        filter.status != null || filter.categoryId != null || !query.isEmpty;
    if (beds.isNotEmpty || (!narrowed && room.beds.isEmpty)) {
      shown.add(BoardRoom(id: room.id, number: room.number, beds: beds));
    }
  }
  overstays.sort((a, b) => a.paidUntil.compareTo(b.paidUntil));
  return BoardView(rooms: shown, counts: counts, overstays: overstays);
}

/// The search box: a room number (exact), part of the occupant's name, or
/// the start of their phone in any common form.
final class _Query {
  const _Query(this.text, this.phone);

  factory _Query.parse(String input) {
    final text = input.trim().toLowerCase();
    var phone = input.replaceAll(RegExp(r'[\s-]'), '');
    if (phone.startsWith('+254')) {
      phone = '0${phone.substring(4)}';
    } else if (phone.startsWith('254')) {
      phone = '0${phone.substring(3)}';
    }
    final digits = phone.replaceAll('+', '');
    final usable = RegExp(r'^\+?\d+$').hasMatch(phone) && digits.length >= 3;
    return _Query(text, usable ? phone : null);
  }

  final String text;
  final String? phone;

  bool get isEmpty => text.isEmpty;

  bool matches(BoardRoom room, BoardBed bed) {
    if (isEmpty) return true;
    if (room.number.toLowerCase() == text) return true;
    final stay = bed.stay;
    if (stay == null) return false;
    if (stay.guestName.toLowerCase().contains(text)) return true;
    final p = phone;
    return p != null && stay.guestPhone.startsWith(p);
  }
}
