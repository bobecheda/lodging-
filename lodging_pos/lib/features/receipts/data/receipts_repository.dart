import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../guests/domain/guest.dart';
import '../../payments/domain/payment_rules.dart';
import '../../setup/domain/prices_settings.dart';
import '../domain/receipt.dart';

/// A receipt in the Receipts list.
final class ReceiptSummary {
  const ReceiptSummary({
    required this.paymentId,
    required this.receiptNumber,
    required this.receivedAt,
    required this.guestName,
    required this.guestPhone,
    required this.roomAndBed,
    required this.total,
    required this.method,
    this.isRefund = false,
  });

  /// The receipt's key: the payment's id, or [refundReceiptKey] for a
  /// REFUND receipt.
  final String paymentId;
  final String receiptNumber;

  /// UTC.
  final DateTime receivedAt;
  final String guestName;

  /// Stored form; lists show it masked.
  final String guestPhone;
  final String roomAndBed;

  /// Whole KES; negative for a REFUND receipt.
  final int total;
  final PaymentMethod method;

  /// A refund payout's REFUND receipt (AD-7).
  final bool isRefund;
}

/// Receipts (FD-6): a payment and its charges, as printed. Reading is open
/// to anyone with [Permission.printReceipts]; printing or saving one counts
/// it (`payment.print`), so later prints say COPY.
class ReceiptsRepository {
  ReceiptsRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  static const listLimit = 50;

  /// The receipt with [key] (a payment's id, or a [refundReceiptKey]),
  /// watched: a print or save turns it into a COPY at once.
  Stream<Receipt> watchReceipt(String key) {
    if (refundIdOfKey(key) case final refundId?) {
      return (_db.select(_db.refunds)..where((r) => r.id.equals(refundId)))
          .watchSingle()
          .asyncMap(_assembleRefund);
    }
    return (_db.select(
      _db.payments,
    )..where((p) => p.id.equals(key))).watchSingle().asyncMap(_assemble);
  }

  Future<Receipt> receipt(String key) async {
    if (refundIdOfKey(key) case final refundId?) {
      return _assembleRefund(
        await (_db.select(
          _db.refunds,
        )..where((r) => r.id.equals(refundId))).getSingle(),
      );
    }
    return _assemble(
      await (_db.select(
        _db.payments,
      )..where((p) => p.id.equals(key))).getSingle(),
    );
  }

  /// Records that [paymentId]'s receipt was printed or saved once more
  /// (`payment.print`). Called only after the print dialog or the save
  /// succeeded.
  Future<void> markPrinted(UserAccount user, String paymentId) async {
    requirePermission(user, Permission.printReceipts);
    if (refundIdOfKey(paymentId) case final refundId?) {
      // A REFUND receipt: `refund.print`.
      await _audit.writeWithAudit(
        action: 'refund.print',
        userId: user.id,
        body: (w) async {
          final refund = await (_db.select(
            _db.refunds,
          )..where((r) => r.id.equals(refundId))).getSingle();
          await w.update(
            _db.refunds,
            refundId,
            RefundsCompanion(printCount: Value(refund.printCount + 1)),
          );
        },
      );
      return;
    }
    await _audit.writeWithAudit(
      action: 'payment.print',
      userId: user.id,
      body: (w) async {
        final payment = await (_db.select(
          _db.payments,
        )..where((p) => p.id.equals(paymentId))).getSingle();
        await w.update(
          _db.payments,
          paymentId,
          PaymentsCompanion(printCount: Value(payment.printCount + 1)),
        );
      },
    );
  }

  /// The newest [listLimit] receipts, or those whose number contains [text]
  /// or whose guest's phone starts with it (FD-3's rule: no name search).
  /// Watched, so a new check-in appears at once.
  Stream<List<ReceiptSummary>> watchReceipts(String text) {
    final number = text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    final byNumber = RegExp(r'^[A-Z]*-?\d+$').hasMatch(number);
    final phone = GuestQuery.parse(text).phonePrefix;
    final searching = text.trim().isNotEmpty;

    final query = _db.select(_db.payments).join([
      innerJoin(
        _db.stayCharges,
        _db.stayCharges.paymentId.equalsExp(_db.payments.id),
      ),
      innerJoin(_db.stays, _db.stays.id.equalsExp(_db.stayCharges.stayId)),
      innerJoin(_db.guests, _db.guests.id.equalsExp(_db.stays.guestId)),
    ]);
    if (searching) {
      query.where(
        Expression.or([
          if (byNumber) _db.payments.receiptNumber.like('%$number%'),
          if (phone != null) _db.guests.phone.like('$phone%'),
          if (!byNumber && phone == null) const Constant(false),
        ]),
      );
    }
    query.orderBy([
      OrderingTerm.desc(_db.payments.receivedAt),
      // Same minute: the later number first.
      OrderingTerm.desc(_db.payments.receiptNumber),
      OrderingTerm.asc(_db.stays.bedLabel),
    ]);
    // Two beds give two rows per payment.
    query.limit(listLimit * 2);

    // REFUND receipts: paid refunds, searched the same way.
    final refunds = _db.select(_db.refunds).join([
      innerJoin(_db.stays, _db.stays.id.equalsExp(_db.refunds.stayId)),
      innerJoin(_db.guests, _db.guests.id.equalsExp(_db.stays.guestId)),
    ])..where(_db.refunds.paidAt.isNotNull());
    if (searching) {
      refunds.where(
        Expression.or([
          if (byNumber) _db.refunds.receiptNumber.like('%$number%'),
          if (phone != null) _db.guests.phone.like('$phone%'),
          if (!byNumber && phone == null) const Constant(false),
        ]),
      );
    }
    refunds
      ..orderBy([OrderingTerm.desc(_db.refunds.paidAt)])
      ..limit(listLimit);

    Future<List<ReceiptSummary>> load() async {
      final rows = await query.get();
      final byPayment = <String, List<TypedResult>>{};
      for (final row in rows) {
        byPayment
            .putIfAbsent(row.readTable(_db.payments).id, () => [])
            .add(row);
      }
      final all = [
        for (final group in byPayment.values.take(listLimit)) _summary(group),
        for (final row in await refunds.get()) _refundSummary(row),
      ];
      // Newest first; the same minute, the later number first.
      all.sort((a, b) {
        final byTime = b.receivedAt.compareTo(a.receivedAt);
        return byTime != 0
            ? byTime
            : b.receiptNumber.compareTo(a.receiptNumber);
      });
      return all.take(listLimit).toList();
    }

    // Read again whenever a payment or a refund (payout, reprint) changes.
    final changes = _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.payments, _db.refunds]),
    );
    return () async* {
      yield await load();
      await for (final _ in changes) {
        yield await load();
      }
    }();
  }

  ReceiptSummary _refundSummary(TypedResult row) {
    final refund = row.readTable(_db.refunds);
    final stay = row.readTable(_db.stays);
    final guest = row.readTable(_db.guests);
    return ReceiptSummary(
      paymentId: refundReceiptKey(refund.id),
      receiptNumber: refund.receiptNumber!,
      receivedAt: refund.paidAt!,
      guestName: guest.fullName,
      guestPhone: guest.phone,
      roomAndBed: 'Room ${stay.roomNumber} · Bed ${stay.bedLabel}',
      total: -refund.amount,
      method: PaymentMethod.parse(refund.method!),
      isRefund: true,
    );
  }

  /// A refund payout's REFUND receipt (AD-7): the nights refunded at the
  /// stay's price, as a negative total.
  Future<Receipt> _assembleRefund(RefundRow refund) async {
    final stay = await (_db.select(
      _db.stays,
    )..where((s) => s.id.equals(refund.stayId))).getSingle();
    final guest = await (_db.select(
      _db.guests,
    )..where((g) => g.id.equals(stay.guestId))).getSingle();
    final charges =
        await (_db.select(_db.stayCharges).join([
                innerJoin(
                  _db.payments,
                  _db.payments.id.equalsExp(_db.stayCharges.paymentId),
                ),
              ])
              ..where(_db.stayCharges.stayId.equals(stay.id))
              ..orderBy([OrderingTerm.asc(_db.stayCharges.periodStart)]))
            .get();
    final decision = await (_db.select(
      _db.refundDecisions,
    )..where((d) => d.refundId.equals(refund.id))).getSingle();
    Future<String> nameOf(String userId) async => (await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(userId))).getSingle()).fullName;
    final settings = {
      for (final s in await _db.select(_db.settings).get()) s.key: s.value,
    };
    final receipts = <String>[];
    for (final c in charges) {
      final number = c.readTable(_db.payments).receiptNumber;
      if (!receipts.contains(number)) receipts.add(number);
    }
    return Receipt(
      lodgingName:
          settings[SettingKeys.lodgingName] ??
          settingDefaults[SettingKeys.lodgingName] ??
          '',
      receiptNumber: refund.receiptNumber!,
      receivedAt: refund.paidAt!,
      guestName: guest.fullName,
      roomNumber: stay.roomNumber,
      lines: [
        ReceiptLine(
          bedLabel: stay.bedLabel,
          categoryName: charges.first.readTable(_db.stayCharges).categoryName,
          nights: refund.nights,
          pricePerNight: refund.pricePerNight,
        ),
      ],
      from: stay.checkInAt,
      checkOutBy: stay.paidUntil,
      method: PaymentMethod.parse(refund.method!),
      mpesaCode: refund.mpesaCode,
      servedBy: await nameOf(refund.paidBy!),
      printCount: refund.printCount,
      graceMinutes: graceMinutesFrom(settings[SettingKeys.graceMinutes]),
      checkedOutAt: stay.checkedOutAt,
      refund: RefundFacts(
        originalReceipts: receipts,
        approvedBy: await nameOf(decision.decidedBy),
        sentTo: refund.payoutPhone,
      ),
    );
  }

  ReceiptSummary _summary(List<TypedResult> rows) {
    final payment = rows.first.readTable(_db.payments);
    final guest = rows.first.readTable(_db.guests);
    final stays = [for (final r in rows) r.readTable(_db.stays)];
    final labels = [for (final s in stays) s.bedLabel]..sort();
    return ReceiptSummary(
      paymentId: payment.id,
      receiptNumber: payment.receiptNumber,
      receivedAt: payment.receivedAt,
      guestName: guest.fullName,
      guestPhone: guest.phone,
      roomAndBed: labels.length == 1
          ? 'Room ${stays.first.roomNumber} · Bed ${labels.single}'
          : 'Room ${stays.first.roomNumber} · Beds ${labels.join(' and ')}',
      total: payment.amount,
      method: PaymentMethod.parse(payment.method),
    );
  }

  Future<Receipt> _assemble(PaymentRow payment) async {
    final rows =
        await (_db.select(_db.stayCharges).join([
                innerJoin(
                  _db.stays,
                  _db.stays.id.equalsExp(_db.stayCharges.stayId),
                ),
              ])
              ..where(_db.stayCharges.paymentId.equals(payment.id))
              ..orderBy([OrderingTerm.asc(_db.stays.bedLabel)]))
            .get();
    final stays = [for (final r in rows) r.readTable(_db.stays)];
    final charges = [for (final r in rows) r.readTable(_db.stayCharges)];
    final guest = await (_db.select(
      _db.guests,
    )..where((g) => g.id.equals(stays.first.guestId))).getSingle();
    final servedBy = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(payment.receivedBy))).getSingle();
    final settings = {
      for (final s in await _db.select(_db.settings).get()) s.key: s.value,
    };

    return Receipt(
      lodgingName:
          settings[SettingKeys.lodgingName] ??
          settingDefaults[SettingKeys.lodgingName] ??
          '',
      receiptNumber: payment.receiptNumber,
      receivedAt: payment.receivedAt,
      guestName: guest.fullName,
      roomNumber: stays.first.roomNumber,
      lines: [
        for (final (i, c) in charges.indexed)
          ReceiptLine(
            bedLabel: stays[i].bedLabel,
            categoryName: c.categoryName,
            nights: c.nights,
            pricePerNight: c.pricePerNight,
          ),
      ],
      from: charges.first.periodStart,
      checkOutBy: charges
          .map((c) => c.periodEnd)
          .reduce((a, b) => a.isAfter(b) ? a : b),
      method: PaymentMethod.parse(payment.method),
      mpesaCode: payment.mpesaCode,
      servedBy: servedBy.fullName,
      printCount: payment.printCount,
      graceMinutes: graceMinutesFrom(settings[SettingKeys.graceMinutes]),
      // A late-checkout payment: the guest has left; say when.
      checkedOutAt: charges.first.kind == 'late_checkout'
          ? stays.first.checkedOutAt
          : null,
      isExtension: charges.first.kind == 'extension',
    );
  }
}
