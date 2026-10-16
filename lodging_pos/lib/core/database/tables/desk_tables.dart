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

/// Close fields (expected_*, counted_cash, variance) are set on close.
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

  @override
  List<String> get customConstraints => [
    "CHECK ((status = 'open') = (closed_at IS NULL))",
    "CHECK (status = 'open' OR (expected_cash IS NOT NULL "
        'AND expected_paybill IS NOT NULL AND counted_cash IS NOT NULL '
        'AND variance IS NOT NULL AND variance = counted_cash - expected_cash))',
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
  IntColumn get printCount => integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => [
    'CHECK (amount = nights * price_per_night)',
    'CHECK ((paid_at IS NULL) = (method IS NULL))',
    'CHECK ((paid_at IS NULL) = (shift_id IS NULL))',
    'CHECK ((paid_at IS NULL) = (paid_by IS NULL))',
    'CHECK ((paid_at IS NULL) = (receipt_number IS NULL))',
    "CHECK ((method IS 'paybill') = (mpesa_code IS NOT NULL))",
  ];
}

@DataClassName('HousekeepingTaskRow')
@TableIndex(name: 'housekeeping_tasks_bed', columns: {#bedId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX housekeeping_tasks_one_open_per_bed '
  'ON housekeeping_tasks (bed_id) WHERE completed_at IS NULL',
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

  @override
  List<String> get customConstraints => [
    'CHECK ((completed_at IS NULL) = (completed_by IS NULL))',
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
