import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/housekeeping/domain/housekeeping.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

void main() {
  group('names: first names, full names when two share one', () {
    test('first names when they differ', () {
      expect(
        housekeeperNames([
          (id: 'r', fullName: 'Rose Akinyi'),
          (id: 'j', fullName: 'Jane Wanjiru'),
        ]),
        {'r': 'Rose', 'j': 'Jane'},
      );
    });

    test('full names for a shared first name only', () {
      expect(
        housekeeperNames([
          (id: 'r1', fullName: 'Rose Akinyi'),
          (id: 'r2', fullName: 'rose  Mutua'),
          (id: 'j', fullName: 'Jane'),
        ]),
        {'r1': 'Rose Akinyi', 'r2': 'rose  Mutua', 'j': 'Jane'},
      );
    });
  });

  test('the To clean tile’s line', () {
    expect(cleaningLine(null), 'Needs cleaning · assign');
    expect(cleaningLine('Rose'), 'Needs cleaning · Rose');
  });

  test('a room needs cleaning while any of its beds does', () {
    expect(roomNeedsCleaning([Cleanliness.clean, Cleanliness.clean]), isFalse);
    expect(
      roomNeedsCleaning([Cleanliness.clean, Cleanliness.notCleaned]),
      isTrue,
    );
    expect(roomNeedsCleaning([]), isFalse);
  });

  group('assignBlocker (FD-9)', () {
    test('only a Not cleaned bed without an open task, to an active '
        'housekeeper', () {
      expect(
        assignBlocker(
          cleanliness: Cleanliness.notCleaned,
          hasOpenTask: false,
          housekeeperActive: true,
        ),
        isNull,
      );
      expect(
        assignBlocker(
          cleanliness: Cleanliness.clean,
          hasOpenTask: false,
          housekeeperActive: true,
        ),
        'This bed is already clean.',
      );
      expect(
        assignBlocker(
          cleanliness: Cleanliness.notCleaned,
          hasOpenTask: true,
          housekeeperActive: true,
        ),
        'Someone is already cleaning this bed. Reassign it instead.',
      );
      expect(
        assignBlocker(
          cleanliness: Cleanliness.notCleaned,
          hasOpenTask: false,
          housekeeperActive: false,
        ),
        'That housekeeper is no longer active. Choose another.',
      );
    });
  });

  group('deactivating a housekeeper with beds to clean', () {
    test('no open task: allowed', () {
      expect(housekeeperDeactivateBlocker('Rose Akinyi', 0), isNull);
    });

    test('says who and what to do (the PRD’s wording)', () {
      expect(
        housekeeperDeactivateBlocker('Rose Akinyi', 1),
        'Rose has a bed to clean. Finish or reassign it first.',
      );
      expect(
        housekeeperDeactivateBlocker('Rose Akinyi', 2),
        'Rose has 2 beds to clean. Finish or reassign them first.',
      );
    });
  });
}
