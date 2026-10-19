import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/domain/receipt.dart';
import 'package:lodging_pos/features/receipts/domain/receipt_number.dart';

DateTime oct(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

Receipt receipt({
  List<ReceiptLine> lines = const [
    ReceiptLine(
      bedLabel: 'A',
      categoryName: 'Comfort',
      nights: 2,
      pricePerNight: 600,
    ),
  ],
  PaymentMethod method = PaymentMethod.paybill,
  String? mpesaCode = 'QJK7H2LM4P',
  int printCount = 0,
  int graceMinutes = 60,
  DateTime? checkedOutAt,
}) => Receipt(
  lodgingName: 'Sunrise Lodge',
  receiptNumber: 'R-000041',
  receivedAt: oct(15, 11, 26),
  guestName: 'Grace Achieng',
  roomNumber: '7',
  lines: lines,
  from: oct(15, 11, 24),
  checkOutBy: oct(17, 10),
  method: method,
  mpesaCode: mpesaCode,
  servedBy: 'Mary Wanjiku',
  printCount: printCount,
  graceMinutes: graceMinutes,
  checkedOutAt: checkedOutAt,
);

void main() {
  test('receipt numbers: prefix, dash, 6 digits', () {
    expect(formatReceiptNumber('R', 41), 'R-000041');
  });

  group('one bed (artboard)', () {
    final r = receipt();

    test('rows as the receipt prints them', () {
      expect(r.issued, 'Thu 15 Oct 2026, 11:26');
      expect(r.roomAndBed, 'Room 7 · Bed A');
      expect(r.category, 'Comfort');
      expect(r.fromText, 'Thu 15 Oct, 11:24');
      expect(r.checkOutByText, 'Sat 17 Oct, 10:00');
      expect(r.chargeRows, [('2 nights', '2 × 600')]);
      expect(r.total, 1200);
      expect(r.totalText, 'KES 1,200');
      expect(r.paidBy, 'M-Pesa');
    });

    test('footer: the stay’s checkout time and the grace setting', () {
      expect(r.footer, [
        'Thank you for staying with us.',
        'Checkout is at 10:00. After 11:00, one more night is charged.',
      ]);
      expect(
        receipt(graceMinutes: 90).footer.last,
        endsWith(
          'After 11:30, '
          'one more night is charged.',
        ),
      );
    });

    test('one night reads "1 night"', () {
      final one = receipt(
        lines: const [
          ReceiptLine(
            bedLabel: 'A',
            categoryName: 'Deluxe',
            nights: 1,
            pricePerNight: 700,
          ),
        ],
      );
      expect(one.chargeRows, [('1 night', '1 × 700')]);
    });
  });

  test('both beds: one room row, a line per bed with its category, one '
      'total; no single category row', () {
    final r = receipt(
      lines: const [
        ReceiptLine(
          bedLabel: 'A',
          categoryName: 'Deluxe',
          nights: 2,
          pricePerNight: 700,
        ),
        ReceiptLine(
          bedLabel: 'B',
          categoryName: 'Comfort',
          nights: 2,
          pricePerNight: 600,
        ),
      ],
    );
    expect(r.roomAndBed, 'Room 7 · Beds A and B');
    expect(r.category, isNull);
    expect(r.chargeRows, [
      ('Bed A · Deluxe', '2 × 700'),
      ('Bed B · Comfort', '2 × 600'),
    ]);
    expect(r.total, 2600);
  });

  test('cash has no M-Pesa code', () {
    final r = receipt(method: PaymentMethod.cash, mpesaCode: null);
    expect(r.paidBy, 'Cash');
    expect(r.mpesaCode, isNull);
  });

  group('COPY: the first print or save is the original', () {
    test('never printed or saved → original', () {
      expect(receipt().isCopy, isFalse);
    });
    test('printed or saved before → COPY', () {
      expect(receipt(printCount: 1).isCopy, isTrue);
      expect(receipt(printCount: 4).isCopy, isTrue);
    });
  });

  group('saving a PDF', () {
    test('folder: the lodging name without characters Windows refuses', () {
      expect(receiptFolderName('Sunrise Lodge'), 'Sunrise Lodge receipts');
      expect(
        receiptFolderName(r'A/B\C:D*E?F"G<H>I|J Lodge'),
        'ABCDEFGHIJ Lodge receipts',
      );
      // Windows also refuses names ending in a dot or space.
      expect(receiptFolderName(' Mama’s Inn. '), 'Mama’s Inn receipts');
      expect(receiptFolderName(':*?'), 'Lodging receipts');
    });

    test('file: the receipt number; a copy says so and is numbered', () {
      expect(receiptFileName(receipt()), 'R-000041.pdf');
      expect(receiptFileName(receipt(printCount: 1)), 'R-000041 COPY 1.pdf');
      expect(receiptFileName(receipt(printCount: 3)), 'R-000041 COPY 3.pdf');
    });
  });

  test('a late-checkout receipt says when they left; no checkout reminder', () {
    final r = receipt(
      lines: const [
        ReceiptLine(
          bedLabel: 'B',
          categoryName: 'Deluxe',
          nights: 1,
          pricePerNight: 700,
        ),
      ],
      checkedOutAt: oct(16, 11, 24),
    );
    expect(r.isLateCheckout, isTrue);
    expect(r.stayRows, [
      ('Charge', 'Late checkout'),
      ('Checked out', 'Fri 16 Oct, 11:24'),
    ]);
    expect(r.chargeRows, [('1 night', '1 × 700')]);
    expect(r.footer, ['Thank you for staying with us.']);
    expect(receipt().stayRows.first.$1, 'From');
  });
}
