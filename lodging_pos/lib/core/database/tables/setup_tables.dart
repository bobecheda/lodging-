// drift column checks refer to their own column by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import 'common.dart';

// Setup tables: owned by the admin.

@DataClassName('UserRow')
class Users extends Table with SyncedColumns {
  TextColumn get fullName => text()();
  TextColumn get username =>
      text().customConstraint('NOT NULL UNIQUE COLLATE NOCASE')();
  TextColumn get passwordHash => text()();
  TextColumn get role => text().check(role.isIn(['admin', 'receptionist']))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get mustChangePassword => boolean()();
}

/// The one synced table without an `id`: `key` is the primary key and sync
/// upserts by `key`.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get updatedBy => text().nullable().references(Users, #id)();
  // Stamped by writeWithAudit, as in SyncedColumns.
  DateTimeColumn get createdAt => dateTime().clientDefault(
    () => throw StateError('stamped by writeWithAudit'),
  )();
  DateTimeColumn get updatedAt => dateTime().clientDefault(
    () => throw StateError('stamped by writeWithAudit'),
  )();
  TextColumn get deviceId => text().clientDefault(
    () => throw StateError('stamped by writeWithAudit'),
  )();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('BedCategoryRow')
class BedCategories extends Table with SyncedColumns {
  TextColumn get name => text().unique()();
  IntColumn get pricePerBlock =>
      integer().check(pricePerBlock.isBiggerThanValue(0))();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('RoomRow')
class Rooms extends Table with SyncedColumns {
  TextColumn get roomNumber => text().unique()();
  TextColumn get floor => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Max 2 active beds per room is enforced in the repository.
@DataClassName('BedRow')
class Beds extends Table with SyncedColumns {
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get label => text().check(label.isIn(['A', 'B']))();
  TextColumn get categoryId => text().references(BedCategories, #id)();
  TextColumn get cleanliness =>
      text().check(cleanliness.isIn(['clean', 'not_cleaned']))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {roomId, label},
  ];
}

@DataClassName('HousekeeperRow')
class Housekeepers extends Table with SyncedColumns {
  TextColumn get fullName => text()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
