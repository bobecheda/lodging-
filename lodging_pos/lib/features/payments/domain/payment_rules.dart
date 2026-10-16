/// How money moves, in or out (BR-10). Money comes in through the cash
/// drawer or the lodging's Paybill, and refunds go out the same two ways.
enum PaymentMethod {
  cash('cash', 'Cash'),
  paybill('paybill', 'M-Pesa');

  const PaymentMethod(this.code, this.label);

  /// As stored in `payments.method` and `refunds.method`.
  final String code;

  /// Shown on screens, receipts and reports.
  final String label;

  static PaymentMethod parse(String code) =>
      values.firstWhere((m) => m.code == code);
}

/// An M-Pesa code that can't be accepted; [message] says why.
class InvalidMpesaCode implements Exception {
  const InvalidMpesaCode(this.message);
  final String message;

  @override
  String toString() => message;
}

/// M-Pesa codes are stored trimmed and uppercase.
String normalizeMpesaCode(String code) => code.trim().toUpperCase();

/// Null if [code] is right for [method]: Paybill needs a code not used
/// before in any payment or refund payout ([codeInUse], looked up by the
/// caller), and cash has none.
String? mpesaCodeError(
  PaymentMethod method,
  String? code, {
  required bool codeInUse,
}) {
  final given = code == null ? '' : normalizeMpesaCode(code);
  return switch (method) {
    PaymentMethod.cash when given.isNotEmpty => 'Cash has no M-Pesa code.',
    PaymentMethod.cash => null,
    PaymentMethod.paybill when given.isEmpty => 'Enter the M-Pesa code.',
    PaymentMethod.paybill when codeInUse =>
      'This M-Pesa code has already been used.',
    PaymentMethod.paybill => null,
  };
}
