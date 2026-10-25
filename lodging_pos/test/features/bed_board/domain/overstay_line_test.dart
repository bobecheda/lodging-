import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import 'bed_board_test.dart' show oct;

/// The owner's Beds alert (Figma "05 Beds"): where and how long, never who.
void main() {
  OverstayAlert alert({
    String room = '5',
    BedLabel label = BedLabel.b,
    required DateTime paidUntil,
    required DateTime graceEnded,
  }) => OverstayAlert(
    stayId: 'st-1',
    roomNumber: room,
    label: label,
    guestName: 'Peter Kamau',
    paidUntil: paidUntil,
    graceEnded: graceEnded,
  );

  test('room and bed, paid-to time, how long past the grace period; no '
      'name', () {
    final a = alert(paidUntil: oct(21, 10), graceEnded: oct(21, 11));
    final line = overstayLine(a, now: oct(21, 11, 40));
    expect(line, 'Room 5 B · paid to 10:00, now 40 min past the grace period.');
    expect(line, isNot(contains('Peter')));
  });

  test('paid to another day says which', () {
    expect(
      overstayLine(
        alert(paidUntil: oct(20, 10), graceEnded: oct(20, 11)),
        now: oct(21, 9),
      ),
      'Room 5 B · paid to yesterday 10:00, now 22 h past the grace period.',
    );
  });

  test('how long: minutes, hours and minutes, days and hours', () {
    expect(formatOverdue(Duration.zero), 'under a minute');
    expect(formatOverdue(const Duration(seconds: 59)), 'under a minute');
    expect(formatOverdue(const Duration(minutes: 1)), '1 min');
    expect(formatOverdue(const Duration(minutes: 59)), '59 min');
    expect(formatOverdue(const Duration(hours: 2)), '2 h');
    expect(formatOverdue(const Duration(hours: 2, minutes: 15)), '2 h 15 min');
    expect(formatOverdue(const Duration(days: 1)), '1 day');
    expect(formatOverdue(const Duration(days: 2, hours: 3)), '2 days 3 h');
  });

  test('the count heads the alert', () {
    expect(overstayCount(1), '1 overstay');
    expect(overstayCount(3), '3 overstays');
  });
}
