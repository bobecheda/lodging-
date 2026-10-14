// drift column checks refer to their own column by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import 'common.dart';
import 'setup_tables.dart';

// Admin-owned records.

/// `target_id` points at `payments` or `stays` depending on `target_type`,
/// so it has no foreign key. A row can be voided only once.
@DataClassName('VoidRow')
class Voids extends Table with SyncedColumns {
  TextColumn get targetType =>
      text().check(targetType.isIn(['payment', 'stay']))();
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
  TextColumn get spentOn =>
      text().check(spentOn.like('____-__-__') & spentOn.length.equals(10))();
  TextColumn get note => text().nullable()();
  TextColumn get recordedBy => text().references(Users, #id)();
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
