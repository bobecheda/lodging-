import 'package:drift/drift.dart';

/// Columns every synced table has (see docs/schema.md, "Common rules").
///
/// All four are optional in the generated `.insert(...)`, but their client
/// defaults throw: only `writeWithAudit` fills them, so an insert that
/// bypasses the writer fails. Pass your own `id` only when you need it to link
/// rows written in the same transaction.
mixin SyncedColumns on Table {
  /// UUID v4.
  TextColumn get id => text().clientDefault(
    () => throw StateError('must be stamped by writeWithAudit'),
  )();
  DateTimeColumn get createdAt => dateTime().clientDefault(
    () => throw StateError('must be stamped by writeWithAudit'),
  )();
  DateTimeColumn get updatedAt => dateTime().clientDefault(
    () => throw StateError('must be stamped by writeWithAudit'),
  )();
  TextColumn get deviceId => text().clientDefault(
    () => throw StateError('must be stamped by writeWithAudit'),
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
