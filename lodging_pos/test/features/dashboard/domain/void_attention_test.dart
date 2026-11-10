import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';

void main() {
  group('Needs your attention: a guest in a bed with a voided payment', () {
    ActiveStayCharges stay(
      String id,
      String bed,
      List<({String receiptNumber, int amount, bool paymentVoided})> charges,
    ) => ActiveStayCharges(
      stayId: id,
      roomNumber: '4',
      bedLabel: bed,
      charges: charges,
    );

    test('only stays with a voided payment, one row each, its charges '
        'summed', () {
      final rows = unpaidStays([
        stay('s-a', 'A', [
          (receiptNumber: 'R-000041', amount: 700, paymentVoided: true),
          (receiptNumber: 'R-000044', amount: 1400, paymentVoided: true),
          (receiptNumber: 'R-000046', amount: 700, paymentVoided: false),
        ]),
        stay('s-b', 'B', [
          (receiptNumber: 'R-000042', amount: 600, paymentVoided: false),
        ]),
      ]);
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.stayId, 's-a');
      expect(r.title, 'Guest in bed, payment voided');
      expect(r.subtitle, 'Room 4 · Bed A · R-000041, R-000044 voided');
      expect(r.figure, 'KES 2,100');
    });

    test('one payment for both beds: each bed counts its own charge', () {
      final rows = unpaidStays([
        stay('s-a', 'A', [
          (receiptNumber: 'R-000050', amount: 700, paymentVoided: true),
        ]),
        stay('s-b', 'B', [
          (receiptNumber: 'R-000050', amount: 600, paymentVoided: true),
        ]),
      ]);
      expect([for (final r in rows) r.figure], ['KES 700', 'KES 600']);
    });
  });

  group('Needs your attention: voids the cloud refused', () {
    test('none: no row', () {
      expect(heldVoidsRow(0), isNull);
    });

    test('one or more', () {
      expect(heldVoidsRow(1)!.title, 'Record not in the cloud');
      expect(
        heldVoidsRow(1)!.subtitle,
        'The cloud refused a void or drawer count; the desk keeps it',
      );
      expect(heldVoidsRow(2)!.title, '2 records not in the cloud');
      expect(
        heldVoidsRow(2)!.subtitle,
        'The cloud refused them; the desk keeps them',
      );
    });
  });
}
