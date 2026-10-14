import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Columns every synced table has (see docs/schema.md, "Common rules").
///
/// All four are optional in the generated `.insert(...)`. `id` defaults to a
/// new UUID; pass one when you need it to link rows in the same transaction.
/// The other three are stamped by `writeWithAudit`; their client default
/// throws, so an insert that bypasses the writer fails.
mixin SyncedColumns on Table {
  /// UUID v4.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
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
  Set<Column<Object>> get primaryKey => {id};
}
