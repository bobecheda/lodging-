/// A payment's receipt (FD-6), as the screen and the PDF print it, and a
/// refund payout's REFUND receipt (AD-7) in the same shape. Pure Dart.
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';

/// One bed's charge on a receipt: [nights] at the stay's locked price, in
/// the category it was let as.
final class ReceiptLine {
  const ReceiptLine({
    required this.bedLabel,
    required this.categoryName,
    required this.nights,
    required this.pricePerNight,
  });

  /// "A" or "B", as let (v3).
  final String bedLabel;
  final String categoryName;
  final int nights;

  /// Whole KES.
  final int pricePerNight;

  int get amount => nights * pricePerNight;
}

/// A REFUND receipt's own facts (AD-7).
final class RefundFacts {
  const RefundFacts({
    required this.originalReceipts,
    required this.approvedBy,
    this.sentTo,
  });

  /// The stay's payment receipt numbers (check-in, extensions).
  final List<String> originalReceipts;

  /// The owner who approved it.
  final String approvedBy;

  /// The phone an M-Pesa payout went to (stored form); null for cash.
  final String? sentTo;
}

/// The receipt key of [refundId]'s REFUND receipt: receipts are opened by a
/// payment's id, or this.
String refundReceiptKey(String refundId) => 'refund:$refundId';

/// The refund id in a [refundReceiptKey], or null for a payment's id.
String? refundIdOfKey(String key) =>
    key.startsWith('refund:') ? key.substring('refund:'.length) : null;

final class Receipt {
  const Receipt({
    required this.lodgingName,
    required this.receiptNumber,
    required this.receivedAt,
    required this.guestName,
    required this.roomNumber,
    required this.lines,
    required this.from,
    required this.checkOutBy,
    required this.method,
    required this.mpesaCode,
    required this.servedBy,
    required this.printCount,
    required this.graceMinutes,
    this.checkedOutAt,
    this.isExtension = false,
    this.refund,
  });

  final String lodgingName;
  final String receiptNumber;

  /// UTC.
  final DateTime receivedAt;
  final String guestName;

  /// As let (v3), not the room's current number.
  final String roomNumber;

  /// One per bed, A before B.
  final List<ReceiptLine> lines;

  /// UTC: when the paid period starts (the check-in time).
  final DateTime from;

  /// UTC: the paid-until time, 10:00.
  final DateTime checkOutBy;
  final PaymentMethod method;
  final String? mpesaCode;

  /// Full name of the user who took the payment.
  final String servedBy;

  /// Times printed or saved so far.
  final int printCount;

  /// The current grace setting, for the footer.
  final int graceMinutes;

  /// UTC. Set on a late-checkout receipt (FD-8): the guest has left, so it
  /// says when instead of a check-out-by time.
  final DateTime? checkedOutAt;

  bool get isLateCheckout => checkedOutAt != null;

  /// An extension's receipt (FD-7): from the old checkout to the new one.
  final bool isExtension;

  /// Set on a REFUND receipt (AD-7): money paid back, as a negative total.
  /// [lines] are the nights refunded at the stay's price; [checkedOutAt]
  /// when the guest left; [servedBy] who paid it out.
  final RefundFacts? refund;

  bool get isRefund => refund != null;

  /// "RECEIPT", or "REFUND" for a refund payout.
  String get title => isRefund ? 'REFUND' : 'RECEIPT';

  /// The first print or save is the original; every later one says COPY.
  /// Viewing on screen doesn't count.
  bool get isCopy => printCount > 0;

  /// `Thu 15 Oct 2026, 11:26`.
  String get issued {
    final year = toNairobi(receivedAt).year;
    return '${formatDayDate(receivedAt)} $year, ${formatTime(receivedAt)}';
  }

  /// `Room 7 · Bed A` or `Room 7 · Beds A and B`.
  String get roomAndBed => lines.length == 1
      ? 'Room $roomNumber · Bed ${lines.single.bedLabel}'
      : 'Room $roomNumber · Beds ${lines.map((l) => l.bedLabel).join(' and ')}';

  /// The single bed's category; null with two beds (each line says its own).
  String? get category => lines.length == 1 ? lines.single.categoryName : null;

  String get fromText => formatDayDateComma(from);
  String get checkOutByText => formatDayDateComma(checkOutBy);

  /// The rows about the stay after room and category: From / Check out by,
  /// or for a late checkout, Charge / Checked out.
  List<(String, String)> get stayRows => switch (checkedOutAt) {
    final DateTime out when refund != null => [
      (
        refund!.originalReceipts.length == 1
            ? 'Original receipt'
            : 'Original receipts',
        refund!.originalReceipts.join(', '),
      ),
      ('Checked out', formatDayDateComma(out)),
    ],
    final DateTime out => [
      ('Charge', 'Late checkout'),
      ('Checked out', formatDayDateComma(out)),
    ],
    null => [
      if (isExtension)
        (
          'Charge',
          'Extension · ${lines.first.nights} '
              '${lines.first.nights == 1 ? 'night' : 'nights'}',
        ),
      ('From', fromText),
      ('Check out by', checkOutByText),
    ],
  };

  /// (label, amount) per bed: `2 nights` · `2 × 600`, or with two beds
  /// `Bed A · Deluxe` · `2 × 700`.
  List<(String, String)> get chargeRows => [
    for (final l in lines)
      (
        lines.length == 1
            ? '${l.nights} ${l.nights == 1 ? 'night' : 'nights'}'
                  '${isRefund ? ' refunded' : ''}'
            : 'Bed ${l.bedLabel} · ${l.categoryName}',
        '${l.nights} × ${_grouped(l.pricePerNight)}',
      ),
  ];

  /// Whole KES; negative on a REFUND receipt (money paid back).
  int get total {
    final sum = lines.fold(0, (sum, l) => sum + l.amount);
    return isRefund ? -sum : sum;
  }

  /// `KES 2,100`, or `− KES 2,100` on a REFUND receipt.
  String get totalText =>
      total < 0 ? '− ${formatKes(-total)}' : formatKes(total);

  String get totalLabel => isRefund ? 'Total refunded' : 'Total paid';
  String get paidBy => method.label;

  /// (label, value, mono) under the total: how it was paid and by whom; a
  /// REFUND receipt also says where an M-Pesa payout went and who approved
  /// it.
  List<(String, String, bool)> get paymentRows => [
    (isRefund ? 'Paid back in' : 'Paid by', method.label, false),
    if (mpesaCode case final code?) ('M-Pesa code', code, true),
    if (refund?.sentTo case final phone?) ('Sent to', maskPhone(phone), false),
    if (refund case final r?) ('Approved by', r.approvedBy, false),
    (isRefund ? 'Paid by' : 'Served by', servedBy, false),
  ];

  /// The stay's checkout time, and when one more night is charged (its
  /// checkout + the grace setting, BR-7a).
  List<String> get footer => [
    'Thank you for staying with us.',
    // The guest has left: no checkout reminder on a late-checkout receipt.
    if (!isLateCheckout)
      'Checkout is at ${formatTime(checkOutBy)}. After '
          '${formatTime(checkOutBy.add(Duration(minutes: graceMinutes)))}, one '
          'more night is charged.',
  ];

  /// `1,200` (no "KES" inside a line).
  static String _grouped(int amount) => formatKes(amount).substring(4);
}

/// Characters Windows doesn't allow in a file or folder name.
final _notInWindowsNames = RegExp(r'[\\/:*?"<>|]');

/// `<lodging name> receipts`, the folder under Documents that Save PDF
/// writes to; characters Windows refuses are removed.
String receiptFolderName(String lodgingName) {
  var name = lodgingName.replaceAll(_notInWindowsNames, '').trim();
  // Windows also refuses a name ending in a dot or a space.
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  return '${name.isEmpty ? 'Lodging' : name} receipts';
}

/// `R-000041.pdf` for the original; a copy is `R-000041 COPY 1.pdf`, so it
/// never overwrites the original.
String receiptFileName(Receipt r) => r.isCopy
    ? '${r.receiptNumber} COPY ${r.printCount}.pdf'
    : '${r.receiptNumber}.pdf';
