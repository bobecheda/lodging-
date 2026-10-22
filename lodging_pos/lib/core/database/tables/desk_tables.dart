// drift column checks refer to their own column by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import 'admin_tables.dart';
import 'common.dart';
import 'setup_tables.dart';

// Front desk tables: owned by the desk.

@DataClassName('GuestRow')
@TableIndex(name: 'guests_phone', columns: {#phone})
@TableIndex(name: 'guests_id_number', columns: {#idNumber})
@TableIndex.sql(
  'CREATE UNIQUE INDEX guests_id_unique ON guests (id_type, id_number) '
  'WHERE id_number IS NOT NULL',
)
class Guests extends Table with SyncedColumns {
  TextColumn get fullName => text()();
  // NOCASE lets type-ahead `LIKE 'prefix%'` use the phone and ID indexes, and
  // makes the ID pair unique regardless of case.
  TextColumn get phone => text().customConstraint('NOT NULL COLLATE NOCASE')();
  TextColumn get idType => text().nullable().check(
    idType.isIn(['national_id', 'passport', 'alien_id']),
  )();
  TextColumn get idNumber =>
      text().nullable().customConstraint('COLLATE NOCASE')();

  @override
  List<String> get customConstraints => [
    'CHECK (id_number IS NULL OR id_type IS NOT NULL)',
  ];
}

/// Close fields (expected_*, counted_cash, variance) are set on close
/// (FD-11). Since v5 also the blind first count, a note, and who closed it
/// (a supervisor may close someone else's). A closed shift never changes
/// again (trigger `shifts_closed_final`).
@DataClassName('ShiftRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX shifts_one_open_per_device ON shifts (device_id) '
  "WHERE status = 'open'",
)
class Shifts extends Table with SyncedColumns {
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get openedAt => dateTime()();
  IntColumn get openingFloat =>
      integer().check(openingFloat.isBiggerOrEqualValue(0))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get expectedCash => integer().nullable()();
  IntColumn get expectedPaybill => integer().nullable()();
  IntColumn get countedCash => integer().nullable()();
  IntColumn get variance => integer().nullable()();
  TextColumn get status => text().check(status.isIn(['open', 'closed']))();

  // v5 (FD-11).
  /// The first, blind count; `counted_cash` is the final one after any
  /// recount. Equal when there was no recount.
  IntColumn get firstCount => integer().nullable()();

  /// Why the cash is short or over; the app requires it when variance != 0.
  TextColumn get closeNote =>
      text().nullable().check(closeNote.length.isSmallerOrEqualValue(200))();
  @ReferenceName('shiftsClosed')
  TextColumn get closedBy => text().nullable().references(Users, #id)();

  @override
  List<String> get customConstraints => [
    "CHECK ((status = 'open') = (closed_at IS NULL))",
    "CHECK (status = 'open' OR (expected_cash IS NOT NULL "
        'AND expected_paybill IS NOT NULL AND counted_cash IS NOT NULL '
        'AND variance IS NOT NULL AND variance = counted_cash - expected_cash))',
    "CHECK ((status = 'open') = (closed_by IS NULL))",
    "CHECK ((status = 'open') = (first_count IS NULL))",
  ];
}

/// `paid_until` = the latest `stay_charges.period_end` of the stay.
@DataClassName('StayRow')
@TableIndex(name: 'stays_guest', columns: {#guestId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX stays_one_active_per_bed ON stays (bed_id) '
  "WHERE status = 'active'",
)
class Stays extends Table with SyncedColumns {
  TextColumn get guestId => text().references(Guests, #id)();
  TextColumn get bedId => text().references(Beds, #id)();
  DateTimeColumn get checkInAt => dateTime()();
  DateTimeColumn get paidUntil => dateTime()();
  DateTimeColumn get checkedOutAt => dateTime().nullable()();
  TextColumn get status => text().check(status.isIn(['active', 'closed']))();
  @ReferenceName('staysCheckedIn')
  TextColumn get checkedInBy => text().references(Users, #id)();
  @ReferenceName('staysCheckedOut')
  TextColumn get checkedOutBy => text().nullable().references(Users, #id)();

  // v3: the room number and bed label at check-in, so a receipt still says
  // what was let after the supervisor renumbers a room (AD-2).
  TextColumn get roomNumber => text()();
  TextColumn get bedLabel => text().check(bedLabel.isIn(['A', 'B']))();

  @override
  List<String> get customConstraints => [
    "CHECK ((status = 'active') = (checked_out_at IS NULL))",
    "CHECK ((status = 'active') = (checked_out_by IS NULL))",
  ];
}

/// A payment is also the receipt.
@DataClassName('PaymentRow')
@TableIndex(name: 'payments_shift', columns: {#shiftId})
class Payments extends Table with SyncedColumns {
  TextColumn get receiptNumber => text().unique()();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get receivedBy => text().references(Users, #id)();
  DateTimeColumn get receivedAt => dateTime()();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get method => text().check(method.isIn(['cash', 'paybill']))();
  TextColumn get mpesaCode =>
      text().nullable().customConstraint('UNIQUE COLLATE NOCASE')();
  IntColumn get printCount => integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => [
    "CHECK ((method = 'paybill') = (mpesa_code IS NOT NULL))",
  ];
}

@DataClassName('StayChargeRow')
@TableIndex(name: 'stay_charges_stay', columns: {#stayId})
@TableIndex(name: 'stay_charges_payment', columns: {#paymentId})
class StayCharges extends Table with SyncedColumns {
  TextColumn get stayId => text().references(Stays, #id)();
  TextColumn get paymentId => text().references(Payments, #id)();
  TextColumn get kind =>
      text().check(kind.isIn(['check_in', 'extension', 'late_checkout']))();
  IntColumn get nights => integer().check(nights.isBiggerOrEqualValue(1))();
  IntColumn get pricePerNight =>
      integer().check(pricePerNight.isBiggerThanValue(0))();
  IntColumn get amount => integer()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();

  // v2: the bed's category at check-in, copied like the price (BR-3), so a
  // receipt never changes and reports group by what was sold. Later charges
  // of the stay reuse the check-in charge's values.
  TextColumn get categoryId => text().references(BedCategories, #id)();
  TextColumn get categoryName => text()();

  @override
  List<String> get customConstraints => [
    'CHECK (amount = nights * price_per_night)',
    'CHECK (period_end > period_start)',
  ];
}

/// A refund of unused prepaid nights (BR-8). Created at early checkout as a
/// request; the payout columns stay null until an approved refund is paid
/// (BR-8b). The approval itself is a `refund_decisions` row. Triggers keep
/// the requested terms fixed, refuse a payout without approval and allow it
/// only once.
@DataClassName('RefundRow')
@TableIndex(name: 'refunds_shift', columns: {#shiftId})
class Refunds extends Table with SyncedColumns {
  TextColumn get stayId => text().unique().references(Stays, #id)();
  IntColumn get nights => integer().check(nights.isBiggerOrEqualValue(1))();
  IntColumn get pricePerNight =>
      integer().check(pricePerNight.isBiggerThanValue(0))();
  IntColumn get amount => integer()();
  @ReferenceName('refundsRequested')
  TextColumn get requestedBy => text().references(Users, #id)();
  DateTimeColumn get requestedAt => dateTime()();

  // Payout, set together once paid.
  TextColumn get method =>
      text().nullable().check(method.isIn(['cash', 'paybill']))();
  TextColumn get mpesaCode =>
      text().nullable().customConstraint('UNIQUE COLLATE NOCASE')();
  TextColumn get shiftId => text().nullable().references(Shifts, #id)();
  @ReferenceName('refundsPaid')
  TextColumn get paidBy => text().nullable().references(Users, #id)();
  DateTimeColumn get paidAt => dateTime().nullable()();
  TextColumn get receiptNumber => text().nullable().unique()();

  /// v7: the phone an M-Pesa payout was sent to (the guest's, editable at
  /// the desk; stored like a guest phone). Null for cash.
  TextColumn get payoutPhone => text().nullable()();
  IntColumn get printCount => integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => [
    'CHECK (amount = nights * price_per_night)',
    'CHECK ((paid_at IS NULL) = (method IS NULL))',
    'CHECK ((paid_at IS NULL) = (shift_id IS NULL))',
    'CHECK ((paid_at IS NULL) = (paid_by IS NULL))',
    'CHECK ((paid_at IS NULL) = (receipt_number IS NULL))',
    "CHECK ((method IS 'paybill') = (mpesa_code IS NOT NULL))",
    "CHECK ((method IS 'paybill') = (payout_phone IS NOT NULL))",
  ];
}

/// A bed to clean (FD-9). Open until completed (the bed becomes clean,
/// BR-9) or, since v4, cancelled when the bed or room is closed (the bed
/// stays not cleaned). Never both.
@DataClassName('HousekeepingTaskRow')
@TableIndex(name: 'housekeeping_tasks_bed', columns: {#bedId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX housekeeping_tasks_one_open_per_bed '
  'ON housekeeping_tasks (bed_id) '
  'WHERE completed_at IS NULL AND cancelled_at IS NULL',
)
class HousekeepingTasks extends Table with SyncedColumns {
  TextColumn get bedId => text().references(Beds, #id)();
  TextColumn get housekeeperId => text().references(Housekeepers, #id)();
  @ReferenceName('housekeepingTasksAssigned')
  TextColumn get assignedBy => text().references(Users, #id)();
  DateTimeColumn get assignedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  @ReferenceName('housekeepingTasksCompleted')
  TextColumn get completedBy => text().nullable().references(Users, #id)();
  // v4: closing the bed or room cancels its open task.
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  @ReferenceName('housekeepingTasksCancelled')
  TextColumn get cancelledBy => text().nullable().references(Users, #id)();

  @override
  List<String> get customConstraints => [
    'CHECK ((completed_at IS NULL) = (completed_by IS NULL))',
    'CHECK ((cancelled_at IS NULL) = (cancelled_by IS NULL))',
    'CHECK (completed_at IS NULL OR cancelled_at IS NULL)',
  ];
}

/// Sprint 3. Stock out may not take an item below zero (repository).
@DataClassName('InventoryMovementRow')
@TableIndex(name: 'inventory_movements_item', columns: {#itemId})
class InventoryMovements extends Table with SyncedColumns {
  TextColumn get itemId => text().references(InventoryItems, #id)();
  TextColumn get direction => text().check(direction.isIn(['in', 'out']))();
  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();
  TextColumn get reason => text()();
  TextColumn get recordedBy => text().references(Users, #id)();
}
