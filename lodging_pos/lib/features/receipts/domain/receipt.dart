/// A payment's receipt (FD-6), as the screen and the PDF print it. Pure
/// Dart. A REFUND receipt (refund payouts) will reuse this shape.
library;

import '../../../core/clock/nairobi.dart';
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
    final DateTime out => [
      ('Charge', 'Late checkout'),
      ('Checked out', formatDayDateComma(out)),
    ],
    null => [('From', fromText), ('Check out by', checkOutByText)],
  };

  /// (label, amount) per bed: `2 nights` · `2 × 600`, or with two beds
  /// `Bed A · Deluxe` · `2 × 700`.
  List<(String, String)> get chargeRows => [
    for (final l in lines)
      (
        lines.length == 1
            ? '${l.nights} ${l.nights == 1 ? 'night' : 'nights'}'
            : 'Bed ${l.bedLabel} · ${l.categoryName}',
        '${l.nights} × ${_grouped(l.pricePerNight)}',
      ),
  ];

  /// Whole KES.
  int get total => lines.fold(0, (sum, l) => sum + l.amount);
  String get totalText => formatKes(total);
  String get paidBy => method.label;

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
