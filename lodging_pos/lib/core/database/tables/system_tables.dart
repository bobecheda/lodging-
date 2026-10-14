// drift column checks refer to their own column by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import 'common.dart';
import 'setup_tables.dart';

// System tables.

/// Append-only and synced. Written only by `writeWithAudit`; no update or
/// delete code exists for it.
@DataClassName('AuditLogRow')
@TableIndex(name: 'audit_log_at', columns: {#at})
@TableIndex(name: 'audit_log_user', columns: {#userId})
@TableIndex(name: 'audit_log_action', columns: {#action})
@TableIndex(name: 'audit_log_entity', columns: {#entity, #entityId})
@TableIndex(name: 'audit_log_operation', columns: {#operationId})
class AuditLog extends Table with SyncedColumns {
  DateTimeColumn get at => dateTime()();

  /// Same UUID on every row written by one writeWithAudit call.
  TextColumn get operationId => text()();

  /// Null for failed logins.
  TextColumn get userId => text().nullable().references(Users, #id)();
  TextColumn get action => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// Null on create.
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text()();
}

/// Local only, never synced. Sent in `seq` order.
@DataClassName('OutboxRow')
@TableIndex.sql(
  'CREATE INDEX outbox_unsent ON outbox (seq) WHERE sent_at IS NULL',
)
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get targetRowId => text().named('row_id')();

  /// The full row after the change.
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
}

/// Local only, never synced. Exactly one row, created in `onCreate`.
@DataClassName('DeviceRow')
class Device extends Table {
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

/// Local only, never synced. Incremented in the same transaction as the
/// payment, so receipt numbers are gap-free per device.
@DataClassName('ReceiptCounterRow')
class ReceiptCounter extends Table {
  TextColumn get deviceId => text().references(Device, #deviceId)();
  IntColumn get nextNumber =>
      integer().check(nextNumber.isBiggerOrEqualValue(1))();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}
