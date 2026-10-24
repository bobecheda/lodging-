/// What the screens show of a refund: the refund with its guest, bed and
/// people, and the owner's detail. Pure Dart, shared by the desk and the
/// owner's phone.
library;

import '../../../core/auth/user_account.dart';
import 'refund.dart';

/// One refund as a list or a screen shows it: the refund, its guest and bed,
/// and who requested, decided and paid it.
final class RefundView {
  const RefundView({
    required this.refund,
    required this.guestName,
    required this.guestPhone,
    required this.roomNumber,
    required this.bedLabel,
    required this.requestedByName,
    this.requestedByRole,
    this.decidedByName,
    this.paidByName,
    this.receiptNumber,
  });

  final Refund refund;
  final String guestName;

  /// Stored form; screens show it masked, except the pay panel's "Send to".
  /// Empty on the owner's phone, which never downloads the full number.
  final String guestPhone;
  final String roomNumber;
  final String bedLabel;
  final String requestedByName;
  final Role? requestedByRole;
  final String? decidedByName;
  final String? paidByName;

  /// The REFUND receipt's number, once paid.
  final String? receiptNumber;

  String get id => refund.id;
  RefundStatus get status => refund.status;
}

/// A charge the refunded stay was paid by: "5 nights × KES 700 · R-000041".
final class PaidCharge {
  const PaidCharge({
    required this.nights,
    required this.pricePerNight,
    required this.receiptNumber,
  });

  final int nights;
  final int pricePerNight;
  final String receiptNumber;
}

/// What the owner sees before deciding (Figma "03 Refund request").
final class RefundDetail {
  const RefundDetail({
    required this.view,
    required this.categoryName,
    required this.checkInAt,
    required this.checkedOutAt,
    required this.charges,
  });

  final RefundView view;
  final String categoryName;

  /// UTC.
  final DateTime checkInAt;

  /// When they left (UTC).
  final DateTime checkedOutAt;
  final List<PaidCharge> charges;

  int get nightsPaid => charges.fold(0, (n, c) => n + c.nights);
  int get nightsNotUsed => view.refund.nights;
  int get nightsUsed => nightsPaid - nightsNotUsed;
}
