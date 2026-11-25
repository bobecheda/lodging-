import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

/// The v2 bed board's words (PR 5, Figma "Desk · Bed board"): one short line
/// per tile, the overstay card's line, the room's categories and when the
/// search box looks for receipts.
void main() {
  // Wed 11 Nov 2026, 12:00 Nairobi.
  final now = nairobiInstant(2026, 11, 11, 12, 0);

  BoardBed bed({
    String guest = 'Peter Kamau',
    DateTime? paidUntil,
    Cleanliness cleanliness = Cleanliness.clean,
    String? cleaner,
    String category = 'c-1',
    String name = 'Comfort',
    String colour = 'teal',
    String label = 'A',
  }) => BoardBed(
    id: 'b-$label',
    label: BedLabel.parse(label),
    categoryId: category,
    categoryName: name,
    categoryColour: colour,
    pricePerNight: 600,
    cleanliness: cleanliness,
    stay: paidUntil == null
        ? null
        : BoardStay(
            stayId: 's-1',
            guestName: guest,
            guestPhone: '0711000482',
            paidUntil: paidUntil,
          ),
    cleaner: cleaner,
  );

  String line(BoardBed b) =>
      tileLine(b, statusOf(b, now: now, graceMinutes: 60), now: now);

  group('a tile’s line', () {
    test('ready', () => expect(line(bed()), 'Ready'));

    test('occupied: the surname and the paid-until weekday', () {
      expect(
        line(
          bed(
            guest: 'Achieng Otieno',
            paidUntil: nairobiInstant(2026, 11, 12, 10, 0),
          ),
        ),
        'Otieno · Thu',
      );
    });

    test('occupied and due out today (in grace): the time', () {
      expect(
        line(bed(paidUntil: nairobiInstant(2026, 11, 11, 11, 30))),
        'Kamau · 11:30',
      );
    });

    test('overstay: the surname and how long past checkout', () {
      expect(
        line(bed(paidUntil: nairobiInstant(2026, 11, 11, 10, 0))),
        'Kamau · 2 h',
      );
    });

    test('to clean, with whoever has it', () {
      expect(line(bed(cleanliness: Cleanliness.notCleaned)), 'To clean');
      expect(
        line(bed(cleanliness: Cleanliness.notCleaned, cleaner: 'Mary')),
        'To clean · Mary',
      );
    });

    test('a one-word name stays whole', () {
      expect(shortGuestName('  Omondi '), 'Omondi');
      expect(shortGuestName('Mercy  Chebet'), 'Chebet');
    });
  });

  test('how long past: minutes, hours, days', () {
    expect(compactOverdue(const Duration(seconds: 30)), '0 min');
    expect(compactOverdue(const Duration(minutes: 45)), '45 min');
    expect(compactOverdue(const Duration(hours: 2, minutes: 50)), '2 h');
    expect(compactOverdue(const Duration(days: 1, hours: 3)), '1 d');
  });

  test('the overstay card: "2 h past 10:00"', () {
    final a = OverstayAlert(
      stayId: 's-1',
      roomNumber: '104',
      label: BedLabel.parse('B'),
      guestName: 'Peter Kamau',
      paidUntil: nairobiInstant(2026, 11, 11, 10, 0),
      graceEnded: nairobiInstant(2026, 11, 11, 11, 0),
    );
    expect(overstayPast(a, now: now), '2 h past 10:00');
    expect(overstayWho(a), '104 B · Kamau');
  });

  group('a room’s categories', () {
    test('one category: its name and colour', () {
      final room = BoardRoom(
        id: 'r',
        number: '104',
        beds: [
          bed(),
          bed(label: 'B'),
        ],
      );
      expect(roomCategories(room), [('Comfort', 'teal')]);
    });

    test('mixed: each once, in bed order', () {
      final room = BoardRoom(
        id: 'r',
        number: '101',
        beds: [
          bed(category: 'c-d', name: 'Deluxe', colour: 'violet'),
          bed(label: 'B', category: 'c-n', name: 'Normal', colour: 'slate'),
        ],
      );
      expect(roomCategories(room), [('Deluxe', 'violet'), ('Normal', 'slate')]);
    });
  });
}
