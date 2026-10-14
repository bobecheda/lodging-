import 'package:drift/drift.dart';

/// Columns every synced table has (see docs/schema.md, "Common rules").
mixin SyncedColumns on Table {
  /// UUID v4.
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
