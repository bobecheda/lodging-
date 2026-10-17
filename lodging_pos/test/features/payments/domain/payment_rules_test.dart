import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';

void main() {
  group('required test case 16: M-Pesa codes (BR-10)', () {
    test('Paybill without a code is rejected', () {
      for (final code in [null, '', '   ']) {
        expect(
          mpesaCodeError(PaymentMethod.paybill, code, codeInUse: false),
          'Enter the M-Pesa code.',
          reason: '"$code"',
        );
      }
    });

    test('a code already used in a payment or refund payout is rejected', () {
      // The caller looks the code up in both payments and refunds; the
      // database also refuses a reused code across the two tables.
      expect(
        mpesaCodeError(PaymentMethod.paybill, 'SJK4H7XQ2P', codeInUse: true),
        'This M-Pesa code has already been used.',
      );
    });

    test('a reused code says where it was used (FD-5)', () {
      final at = DateTime.utc(2026, 10, 15, 8, 2); // Thu 11:02 Nairobi
      expect(
        mpesaCodeError(
          PaymentMethod.paybill,
          ' qjk7h2lm4p ',
          codeInUse: true,
          usedOn: MpesaCodeUse(receiptNumber: 'R-000038', at: at),
        ),
        'QJK7H2LM4P was already used on receipt R-000038 (Thu 15 Oct, '
        '11:02).',
      );
      expect(
        mpesaCodeError(
          PaymentMethod.paybill,
          'QJK7H2LM4P',
          codeInUse: true,
          usedOn: MpesaCodeUse(
            receiptNumber: 'R-000040',
            at: at,
            isRefund: true,
          ),
        ),
        'QJK7H2LM4P was already used on refund receipt R-000040 (Thu 15 '
        'Oct, 11:02).',
      );
    });

    test('cash with a code is rejected', () {
      expect(
        mpesaCodeError(PaymentMethod.cash, 'SJK4H7XQ2P', codeInUse: false),
        'Cash has no M-Pesa code.',
      );
    });

    test('valid: Paybill with a new code, cash with none', () {
      expect(
        mpesaCodeError(PaymentMethod.paybill, 'SJK4H7XQ2P', codeInUse: false),
        isNull,
      );
      expect(
        mpesaCodeError(PaymentMethod.cash, null, codeInUse: false),
        isNull,
      );
      expect(
        mpesaCodeError(PaymentMethod.cash, '  ', codeInUse: false),
        isNull,
      );
    });

    test('codes are stored trimmed and uppercase', () {
      expect(normalizeMpesaCode(' sjk4h7xq2p '), 'SJK4H7XQ2P');
    });
  });

  test(
    'both methods are stored as cash | paybill; Paybill shows as M-Pesa',
    () {
      expect(
        [for (final m in PaymentMethod.values) m.code],
        ['cash', 'paybill'],
      );
      expect(PaymentMethod.parse('paybill'), PaymentMethod.paybill);
      expect(PaymentMethod.cash.label, 'Cash');
      expect(PaymentMethod.paybill.label, 'M-Pesa');
    },
  );
}
