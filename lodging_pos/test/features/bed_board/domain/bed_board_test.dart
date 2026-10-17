import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';
import 'package:lodging_pos/features/setup/domain/prices_settings.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

DateTime oct(int day, int hour, [int minute = 0, int second = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute, second);

BoardBed bed(
  String id, {
  BedLabel label = BedLabel.a,
  String category = 'Deluxe',
  String categoryId = 'deluxe',
  Cleanliness cleanliness = Cleanliness.clean,
  BoardStay? stay,
}) => BoardBed(
  id: id,
  label: label,
  categoryId: categoryId,
  categoryName: category,
  pricePerNight: 700,
  cleanliness: cleanliness,
  stay: stay,
);

BoardStay stay(
  String name,
  DateTime paidUntil, {
  String phone = '0722418905',
}) => BoardStay(guestName: name, guestPhone: phone, paidUntil: paidUntil);

void main() {
  const grace = 60;
  final paid = oct(16, 10); // Fri 10:00

  group('statusOf (derived, never stored)', () {
    test('no stay: clean is Ready, not cleaned is To clean', () {
      expect(
        statusOf(bed('a'), now: oct(16, 9), graceMinutes: grace),
        BoardStatus.ready,
      );
      expect(
        statusOf(
          bed('a', cleanliness: Cleanliness.notCleaned),
          now: oct(16, 9),
          graceMinutes: grace,
        ),
        BoardStatus.toClean,
      );
    });

    test('a stay is In use until paid_until + grace, then Overstay', () {
      final b = bed('a', stay: stay('Peter Kamau', paid));
      BoardStatus at(DateTime now) =>
          statusOf(b, now: now, graceMinutes: grace);
      expect(at(oct(16, 10, 59)), BoardStatus.occupied);
      expect(at(oct(16, 11)), BoardStatus.occupied);
      expect(at(oct(16, 11, 0, 1)), BoardStatus.overstay);
    });

    test('the grace setting moves the line', () {
      final b = bed('a', stay: stay('Peter Kamau', paid));
      expect(
        statusOf(b, now: oct(16, 10, 1), graceMinutes: 0),
        BoardStatus.overstay,
      );
    });
  });

  test('graceMinutesFrom reads the setting, with 60 for anything unusable', () {
    expect(graceMinutesFrom('45'), 45);
    expect(graceMinutesFrom('0'), 0);
    for (final bad in [null, '', '181', 'x']) {
      expect(graceMinutesFrom(bad), 60, reason: '$bad');
    }
  });

  group('the board', () {
    final rooms = [
      BoardRoom(id: 'r10', number: '10', beds: [bed('10a')]),
      BoardRoom(
        id: 'r2',
        number: '2',
        beds: [
          bed('2a', stay: stay('Grace Achieng', oct(17, 10))),
          bed(
            '2b',
            label: BedLabel.b,
            category: 'Normal',
            categoryId: 'normal',
            cleanliness: Cleanliness.notCleaned,
          ),
        ],
      ),
      BoardRoom(
        id: 'r5',
        number: '5',
        beds: [
          bed('5a', stay: stay('Peter Kamau', paid, phone: '+256712345678')),
        ],
      ),
    ];
    final now = oct(16, 11, 30); // Peter overstays, Grace doesn't.

    BoardView view({
      BoardStatus? status,
      String? categoryId,
      String query = '',
    }) => boardView(
      rooms,
      BoardFilter(status: status, categoryId: categoryId, query: query),
      now: now,
      graceMinutes: grace,
    );

    test('rooms in natural order; counts add up to all beds', () {
      final v = view();
      expect([for (final r in v.rooms) r.number], ['2', '5', '10']);
      expect(v.counts, {
        BoardStatus.ready: 1,
        BoardStatus.occupied: 1,
        BoardStatus.overstay: 1,
        BoardStatus.toClean: 1,
      });
      expect(v.total, 4);
    });

    test('a status filter keeps only rooms with matching beds; counts stay '
        'for every status', () {
      final v = view(status: BoardStatus.toClean);
      expect([for (final r in v.rooms) r.number], ['2']);
      expect([for (final b in v.rooms.single.beds) b.id], ['2b']);
      expect(v.counts[BoardStatus.ready], 1);
    });

    test('a category filter narrows beds and counts', () {
      final v = view(categoryId: 'normal');
      expect([for (final r in v.rooms) r.number], ['2']);
      expect(v.total, 1);
      expect(v.counts[BoardStatus.toClean], 1);
      expect(v.counts[BoardStatus.ready], 0);
    });

    test('search: room number, occupant name, or occupant phone', () {
      List<String> ids(String q) => [
        for (final r in view(query: q).rooms)
          for (final b in r.beds) b.id,
      ];
      expect(ids('10'), ['10a']);
      expect(ids('5'), ['5a']); // room 5 only, not every bed
      expect(ids('grace'), ['2a']);
      expect(ids('kamau'), ['5a']);
      expect(ids('0722 41'), ['2a']); // phone prefix, any spacing
      expect(ids('+254 722'), ['2a']); // Kenyan forms normalized
      expect(ids('+2567'), ['5a']);
      expect(ids('nobody'), isEmpty);
      expect(ids('  '), ['2a', '2b', '5a', '10a']);
    });

    test('overstays are listed for the bar, oldest first', () {
      final v = view();
      expect(v.overstays, hasLength(1));
      final o = v.overstays.single;
      expect(
        (o.roomNumber, o.label, o.guestName, o.paidUntil),
        ('5', BedLabel.a, 'Peter Kamau', paid),
      );
      expect(o.graceEnded, oct(16, 11));
    });

    test('the bar lists every overstay even when filtered out', () {
      expect(view(status: BoardStatus.ready).overstays, hasLength(1));
    });
  });
}
