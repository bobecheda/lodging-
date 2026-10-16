/// Receipt numbers: the settings prefix, a dash and 6 digits, e.g.
/// `R-000041`. Payments and refund payouts draw from one gap-free counter
/// per device (`receipt_counter`).
String formatReceiptNumber(String prefix, int number) =>
    '$prefix-${number.toString().padLeft(6, '0')}';
