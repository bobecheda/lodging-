import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../clock/clock.dart';
import '../database/database.dart';
import '../database/database_provider.dart';

part 'audit_writer.g.dart';

/// JSON for audit and outbox payloads: SQL column names as keys (build.yaml)
/// and ISO-8601 UTC timestamps, so payloads map 1:1 to the Postgres mirror.
const auditJsonSerializer = ValueSerializer.defaults(
  serializeDateTimeValuesAsString: true,
);

final _actionPattern = RegExp(r'^[a-z_]+\.[a-z_]+$');

/// Written only by [AuditWriter] itself or by the database's `onCreate`.
const _systemTables = {'audit_log', 'outbox', 'device'};

/// Changed inside the transaction, but never audited or synced.
const _localOnlyTables = {'receipt_counter'};

/// The single write path. Repositories never write to drift directly.
class AuditWriter {
  AuditWriter(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Runs [body] in one transaction. For every synced row [body] inserts or
  /// updates through [AuditedWrites], it also writes one `audit_log` row
  /// (before/after of that row, tagged with [action]) and outbox rows for the
  /// business row and the audit row, in write order. All audit rows of one
  /// call share an `operation_id`.
  ///
  /// If anything throws, nothing is saved.
  ///
  /// [action] is `entity.verb`, e.g. `stay.check_in`. [userId] is the user
  /// doing it.
  Future<T> writeWithAudit<T>({
    required String action,
    required String? userId,
    required Future<T> Function(AuditedWrites w) body,
  }) {
    _checkAction(action);
    return _db.transaction(() async {
      final w = await _start();
      final result = await body(w);
      if (w._changes.isEmpty) {
        throw StateError(
          '$action changed no synced rows; use recordEvent for audit-only '
          'entries',
        );
      }
      for (final c in w._changes) {
        await w._enqueue(c.table, c.id, c.afterJson);
        await w._audit(
          action: action,
          userId: userId,
          entity: c.table,
          entityId: c.id,
          beforeJson: c.beforeJson,
          afterJson: c.afterJson,
        );
      }
      return result;
    });
  }

  /// Writes an audit entry for an event that changes no business rows, such
  /// as `user.login` or `user.login_failed` ([userId] null).
  Future<void> recordEvent({
    required String action,
    required String? userId,
    required String entity,
    required String entityId,
    Map<String, Object?> details = const {},
  }) {
    _checkAction(action);
    return _db.transaction(() async {
      final w = await _start();
      await w._audit(
        action: action,
        userId: userId,
        entity: entity,
        entityId: entityId,
        beforeJson: null,
        afterJson: jsonEncode(details),
      );
    });
  }

  Future<AuditedWrites> _start() async => AuditedWrites._(
    _db,
    now: _clock.now(),
    deviceId: await _db.deviceId(),
    operationId: const Uuid().v4(),
  );

  static void _checkAction(String action) {
    if (!_actionPattern.hasMatch(action)) {
      throw ArgumentError.value(action, 'action', 'must be entity.verb');
    }
  }
}

/// The writes allowed inside [AuditWriter.writeWithAudit].
///
/// Reads through the database inside the body see the transaction, so
/// repositories may query `db` directly before writing.
class AuditedWrites {
  AuditedWrites._(
    this._db, {
    required this.now,
    required this.deviceId,
    required this.operationId,
  });

  final AppDatabase _db;

  /// "Now" for this whole write. Use it for business timestamps too
  /// (e.g. `check_in_at`) so they match the audit entry.
  final DateTime now;

  /// This install's device id.
  final String deviceId;

  /// `audit_log.operation_id` for every audit row of this call.
  final String operationId;

  final _changes = <_Change>[];

  String newId() => const Uuid().v4();

  /// Inserts [row] and returns it as stored.
  ///
  /// Build [row] with the companion's `.insert(...)`, so business fields are
  /// checked at compile time. `id` gets a new UUID (client default) unless
  /// [row] has one to link rows in this transaction.
  ///
  /// On synced tables, stamps `created_at`, `updated_at` (= [now]) and
  /// `device_id` in the column map, overriding any value in [row]. Their
  /// client defaults throw, so only this method can fill them.
  Future<D> insert<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    Insertable<D> row,
  ) async {
    final name = _writableName(table);
    final synced = !_localOnlyTables.contains(name);
    final values = {
      ...row.toColumns(true),
      if (synced) ...{
        'created_at': Variable<DateTime>(now),
        'updated_at': Variable<DateTime>(now),
        'device_id': Variable<String>(deviceId),
      },
    };

    final inserted = await _db
        .into(table)
        .insertReturning(RawValuesInsertable<D>(values));
    if (synced) _record(table, before: null, after: inserted);
    return inserted;
  }

  /// Updates the row whose primary key is [id] with [changes] and returns it
  /// as stored. Throws if the row does not exist.
  ///
  /// On synced tables, stamps `updated_at` = [now] and `device_id`. Never
  /// writes `created_at`: [changes] may not touch it, the primary key or
  /// `device_id`.
  Future<D> update<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    String id,
    Insertable<D> changes,
  ) async {
    final name = _writableName(table);
    final pk = _primaryKey(table);
    final changed = changes.toColumns(true);
    for (final column in {pk.name, 'created_at', 'device_id'}) {
      if (changed.containsKey(column)) {
        throw ArgumentError('$name.$column cannot be changed by an update');
      }
    }
    if (changed.isEmpty) throw ArgumentError('No changes for $name $id');

    final synced = !_localOnlyTables.contains(name);
    final values = {
      ...changed,
      if (synced) ...{
        'updated_at': Variable<DateTime>(now),
        'device_id': Variable<String>(deviceId),
      },
    };

    Future<D?> read() =>
        (_db.select(table)..where((_) => pk.equals(id))).getSingleOrNull();

    final before = await read();
    if (before == null) throw StateError('$name $id not found');
    await (_db.update(
      table,
    )..where((_) => pk.equals(id))).write(RawValuesInsertable<D>(values));
    final after = (await read())!;
    if (synced) _record(table, before: before, after: after);
    return after;
  }

  void _record(
    TableInfo table, {
    required DataClass? before,
    required DataClass after,
  }) {
    final afterMap = after.toJson(serializer: auditJsonSerializer);
    _changes.add(
      _Change(
        table: table.actualTableName,
        id: afterMap[_primaryKey(table).name] as String,
        beforeJson: before == null
            ? null
            : jsonEncode(before.toJson(serializer: auditJsonSerializer)),
        afterJson: jsonEncode(afterMap),
      ),
    );
  }

  Future<void> _audit({
    required String action,
    required String? userId,
    required String entity,
    required String entityId,
    required String? beforeJson,
    required String afterJson,
  }) async {
    final row = await _db
        .into(_db.auditLog)
        .insertReturning(
          AuditLogCompanion.insert(
            id: Value(newId()),
            createdAt: Value(now),
            updatedAt: Value(now),
            deviceId: Value(deviceId),
            at: now,
            operationId: operationId,
            userId: Value(userId),
            action: action,
            entity: entity,
            entityId: entityId,
            beforeJson: Value(beforeJson),
            afterJson: afterJson,
          ),
        );
    await _enqueue(
      'audit_log',
      row.id,
      jsonEncode(row.toJson(serializer: auditJsonSerializer)),
    );
  }

  Future<void> _enqueue(String table, String rowId, String payloadJson) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(
          targetTable: table,
          targetRowId: rowId,
          payloadJson: payloadJson,
          createdAt: now,
        ),
      );

  static String _writableName(TableInfo table) {
    final name = table.actualTableName;
    if (_systemTables.contains(name)) {
      throw ArgumentError('$name is not written through writeWithAudit');
    }
    return name;
  }

  static GeneratedColumn<String> _primaryKey(TableInfo table) =>
      table.$primaryKey.single as GeneratedColumn<String>;
}

class _Change {
  const _Change({
    required this.table,
    required this.id,
    required this.beforeJson,
    required this.afterJson,
  });

  final String table;
  final String id;
  final String? beforeJson;
  final String afterJson;
}

@Riverpod(keepAlive: true)
AuditWriter auditWriter(Ref ref) =>
    AuditWriter(ref.watch(appDatabaseProvider), ref.watch(clockProvider));
