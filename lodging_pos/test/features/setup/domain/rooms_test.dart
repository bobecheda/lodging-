import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

BedSummary bed(
  BedLabel label, {
  bool active = true,
  bool guest = false,
  String category = 'deluxe',
}) => BedSummary(
  id: 'bed-${label.name}',
  label: label,
  categoryId: category,
  categoryName: 'Deluxe',
  pricePerNight: 700,
  cleanliness: Cleanliness.clean,
  isActive: active,
  hasActiveStay: guest,
);

RoomSummary room(List<BedSummary> beds, {bool active = true}) => RoomSummary(
  id: 'room-5',
  number: '5',
  floor: 'Ground',
  notes: null,
  isActive: active,
  beds: beds,
);

void main() {
  group('room numbers', () {
    test('are trimmed and uppercased', () {
      expect(normalizeRoomNumber('  3a '), '3A');
    });

    test('are 1–10 letters, digits or dashes', () {
      for (final ok in ['1', '12', '3A', 'B-12', 'ANNEX1']) {
        expect(roomNumberError(ok), isNull, reason: ok);
      }
      for (final bad in ['', '  ', '12345678901', 'Room 5', '5/6']) {
        expect(roomNumberError(bad), isNotNull, reason: bad);
      }
    });

    test('sort naturally: 2 before 10, letters after digits', () {
      final sorted = ['10', '2', '1', '2A', 'ANNEX', '13']
        ..sort(compareRoomNumbers);
      expect(sorted, ['1', '2', '2A', '10', '13', 'ANNEX']);
    });
  });

  group('validateNewRoom', () {
    const active = {'vip', 'deluxe'};
    NewRoom input({String number = '5', String? bedB}) => NewRoom(
      number: number,
      floor: 'Ground',
      notes: null,
      bedACategoryId: 'deluxe',
      bedBCategoryId: bedB,
    );

    test('a 1-bed or 2-bed room with active categories is valid', () {
      expect(validateNewRoom(input(), activeCategoryIds: active), isEmpty);
      expect(
        validateNewRoom(input(bedB: 'vip'), activeCategoryIds: active),
        isEmpty,
      );
    });

    test('rejects a bad number and an inactive category', () {
      final errors = validateNewRoom(
        input(number: 'Room 5', bedB: 'closed-category'),
        activeCategoryIds: active,
      );
      expect(errors.keys, {RoomField.number, RoomField.bedB});
    });
  });

  group('deactivating a bed', () {
    test('is blocked while it has a guest', () {
      final b = bed(BedLabel.b, guest: true);
      expect(
        deactivateBedBlocker(b, room([bed(BedLabel.a), b])),
        'Bed B has a guest right now. Check them out first.',
      );
    });

    test("is blocked for an active room's last active bed", () {
      final a = bed(BedLabel.a);
      expect(
        deactivateBedBlocker(a, room([a, bed(BedLabel.b, active: false)])),
        'Deactivate the room instead.',
      );
    });

    test('is allowed for the last bed of a closed room', () {
      final a = bed(BedLabel.a);
      expect(deactivateBedBlocker(a, room([a], active: false)), isNull);
    });

    test('is allowed for one of two active beds with no guest', () {
      final b = bed(BedLabel.b);
      expect(deactivateBedBlocker(b, room([bed(BedLabel.a), b])), isNull);
    });
  });

  group('deactivating a room', () {
    test('is blocked while any bed has a guest', () {
      expect(
        deactivateRoomBlocker(
          room([bed(BedLabel.a), bed(BedLabel.b, guest: true)]),
        ),
        'Bed B has a guest right now. Check them out first.',
      );
      expect(
        deactivateRoomBlocker(
          room([bed(BedLabel.a, guest: true), bed(BedLabel.b, guest: true)]),
        ),
        'Beds A and B have guests right now. Check them out first.',
      );
    });

    test('is allowed with no guests', () {
      expect(deactivateRoomBlocker(room([bed(BedLabel.a)])), isNull);
    });
  });

  group('reactivating a room', () {
    test('needs at least one active bed', () {
      expect(
        reactivateRoomBlocker(
          room([bed(BedLabel.a, active: false)], active: false),
        ),
        'Reactivate a bed first.',
      );
      expect(
        reactivateRoomBlocker(room([bed(BedLabel.a)], active: false)),
        isNull,
      );
    });
  });

  group('adding a bed', () {
    test('only a room with bed A alone can get bed B', () {
      expect(addBedBlocker(room([bed(BedLabel.a)])), isNull);
      expect(
        addBedBlocker(room([bed(BedLabel.a), bed(BedLabel.b)])),
        'This room already has beds A and B.',
      );
      // A closed bed B is reactivated, not replaced.
      expect(
        addBedBlocker(room([bed(BedLabel.a), bed(BedLabel.b, active: false)])),
        'Bed B is closed. Reactivate it instead.',
      );
    });
  });
}
