// drift column checks refer to their own column by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import 'common.dart';
import 'desk_tables.dart';
import 'setup_tables.dart';

// Admin-owned records.

/// `target_id` points at `payments`, `stays` or `refunds` (a refund's payout)
/// depending on `target_type`, so it has no foreign key. A row can be voided
/// only once.
@DataClassName('VoidRow')
class Voids extends Table with SyncedColumns {
  TextColumn get targetType =>
      text().check(targetType.isIn(['payment', 'stay', 'refund']))();
  TextColumn get targetId => text()();
  TextColumn get reason =>
      text().check(reason.trim().length.isBiggerThanValue(0))();
  TextColumn get voidedBy => text().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {targetType, targetId},
  ];
}

/// An admin's decision on a refund request (BR-8a): one per refund, written
/// once and never changed. Admin-owned like `voids`, so the `refunds` row
/// keeps a single writer (the desk).
@DataClassName('RefundDecisionRow')
class RefundDecisions extends Table with SyncedColumns {
  TextColumn get refundId => text().unique().references(Refunds, #id)();
  TextColumn get decision =>
      text().check(decision.isIn(['approved', 'rejected']))();
  TextColumn get note => text().nullable()();
  TextColumn get decidedBy => text().references(Users, #id)();
  DateTimeColumn get decidedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    "CHECK (decision = 'approved' OR coalesce(length(trim(note)), 0) > 0)",
  ];
}

/// v8: the owner's answer to a price request (BR-2): one per request, written
/// once and never changed. Owner-owned like `refund_decisions`; an approval
/// changes the category's price in the same transaction.
@DataClassName('PriceDecisionRow')
class PriceDecisions extends Table with SyncedColumns {
  TextColumn get requestId => text().unique().references(PriceRequests, #id)();
  TextColumn get decision =>
      text().check(decision.isIn(['approved', 'rejected']))();
  TextColumn get note => text().nullable()();
  TextColumn get decidedBy => text().references(Users, #id)();
  DateTimeColumn get decidedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    "CHECK (decision = 'approved' OR coalesce(length(trim(note)), 0) > 0)",
  ];
}

/// Sprint 3. `spent_on` is a Nairobi calendar date, `YYYY-MM-DD`.
@DataClassName('ExpenseRow')
class Expenses extends Table with SyncedColumns {
  TextColumn get category => text().check(
    category.isIn([
      'laundry',
      'utilities',
      'wages',
      'supplies',
      'repairs',
      'other',
    ]),
  )();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get spentOn => text()();
  TextColumn get note => text().nullable()();
  TextColumn get recordedBy => text().references(Users, #id)();

  @override
  List<String> get customConstraints => [
    "CHECK (spent_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
  ];
}

/// Sprint 3.
@DataClassName('InventoryItemRow')
class InventoryItems extends Table with SyncedColumns {
  TextColumn get name => text().unique()();
  TextColumn get unit => text()();
  IntColumn get lowStockLevel =>
      integer().check(lowStockLevel.isBiggerOrEqualValue(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
