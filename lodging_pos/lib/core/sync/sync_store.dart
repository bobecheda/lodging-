import 'dart:convert';

import 'package:drift/drift.dart';

import '../audit/audit_writer.dart';
import '../database/database.dart';
import 'cloud.dart';

/// The desk's side of sync in the database: its bookkeeping (`sync_state`),
/// the outbox queue, and the first upload's snapshot reads. Local only;
/// nothing here goes through the writer or is audited.
class SyncStore {
  SyncStore(this._db);

  final AppDatabase _db;

  // ── Keys in sync_state ─────────────────────────────────────────────────

  /// The desk's cloud account email; present once connected.
  static const deskEmail = 'desk_email';

  /// The owner's cloud email (their sign-in on the phone).
  static const ownerEmail = 'owner_email';

  /// The first upload: the outbox's highest seq when it started (rows up
  /// to it are covered by the snapshot), how many rows it has and has
  /// sent, the last key sent per table ("*" once a table is done), and
  /// "yes" once the cloud has it all.
  static const uploadMaxSeq = 'upload.max_seq';
  static const uploadTotal = 'upload.total';
  static const uploadSent = 'upload.sent';
  static String uploadAfter(String table) => 'upload.after.$table';
  static const uploadDone = 'upload.done';

  static const lastPushAt = 'last_push_at';

  /// The refused row stopping the queue: "table id: message".
  static const problem = 'problem';

  /// The pull's cursor: the last `server_seq` applied (sync-2).
  static const pullAfter = 'pull.after';

  /// The PC's clock minus the server's, in seconds, from the last pull.
  static const clockOffset = 'clock.offset_s';

  /// "on" while the clock warning lasts (an episode), across restarts.
  static const clockWarning = 'clock.warning';

  // ── What goes up, in which order ───────────────────────────────────────

  /// The desk's tables, parents before children, so every foreign key
  /// finds its row already in the cloud.
  static const deskTables = [
    'users',
    'settings',
    'bed_categories',
    'rooms',
    'beds',
    'housekeepers',
    'guests',
    'shifts',
    'stays',
    'payments',
    'stay_charges',
    'refunds',
    'price_requests',
    'housekeeping_tasks',
    'inventory_items',
    'inventory_movements',
    'voids',
    'expenses',
    'audit_log',
  ];

  /// The owner's tables: written in the cloud first, only through the
  /// owner's sign-in (the first upload sends the earlier ones).
  static const ownerTables = ['refund_decisions', 'price_decisions'];

  // ── Bookkeeping ────────────────────────────────────────────────────────

  Future<String?> get(String key) async => (await (_db.select(
    _db.syncState,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<int> getInt(String key) async =>
      int.tryParse(await get(key) ?? '') ?? 0;

  /// Stores [value] under [key]; null removes it.
  Future<void> set(String key, Object? value) async {
    if (value == null) {
      await (_db.delete(_db.syncState)..where((s) => s.key.equals(key))).go();
    } else {
      await _db
          .into(_db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(key: key, value: '$value'),
          );
    }
  }

  /// Removes every key starting with [prefix].
  Future<void> clear(String prefix) =>
      (_db.delete(_db.syncState)..where((s) => s.key.like('$prefix%'))).go();

  // ── The outbox ─────────────────────────────────────────────────────────

  Future<int> pendingCount() async {
    final count = countAll(filter: _db.outbox.sentAt.isNull());
    return (await (_db.selectOnly(
      _db.outbox,
    )..addColumns([count])).getSingle()).read(count)!;
  }

  Stream<int> watchPending() {
    final count = countAll(filter: _db.outbox.sentAt.isNull());
    return (_db.selectOnly(
      _db.outbox,
    )..addColumns([count])).map((r) => r.read(count)!).watchSingle();
  }

  /// The oldest [limit] unsent rows, in the order they were written.
  Future<List<OutboxRow>> unsent({required int limit}) =>
      (_db.select(_db.outbox)
            ..where((o) => o.sentAt.isNull())
            ..orderBy([(o) => OrderingTerm.asc(o.seq)])
            ..limit(limit))
          .get();

  /// The highest seq written so far (0 for an empty outbox).
  Future<int> maxSeq() async {
    final max = _db.outbox.seq.max();
    return (await (_db.selectOnly(
          _db.outbox,
        )..addColumns([max])).getSingle()).read(max) ??
        0;
  }

  Future<void> markSent(Iterable<int> seqs, DateTime at) =>
      (_db.update(_db.outbox)..where((o) => o.seq.isIn(seqs))).write(
        OutboxCompanion(sentAt: Value(at), lastError: const Value(null)),
      );

  /// The snapshot covered these: rows up to [seq] still unsent.
  Future<void> markSentUpTo(int seq, DateTime at) =>
      (_db.update(
            _db.outbox,
          )..where((o) => o.seq.isSmallerOrEqualValue(seq) & o.sentAt.isNull()))
          .write(OutboxCompanion(sentAt: Value(at)));

  Future<void> recordFailure(int seq, String error) => _db.customUpdate(
    'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE seq = ?',
    variables: [Variable.withString(error), Variable.withInt(seq)],
    updates: {_db.outbox},
  );

  /// Sent rows older than [before] are dropped; unsent ones are kept.
  Future<int> pruneSent(DateTime before) => (_db.delete(
    _db.outbox,
  )..where((o) => o.sentAt.isSmallerThanValue(before))).go();

  /// The outbox row as the cloud takes it.
  static CloudRow fromOutbox(OutboxRow o) => cloudRow(
    o.targetTable,
    (jsonDecode(o.payloadJson) as Map).cast<String, Object?>(),
  );

  /// A row as it goes up: no password hash ever leaves the desk, and rows
  /// queued before v6 say `supervisor`, not `admin`.
  static CloudRow cloudRow(String table, Map<String, Object?> row) {
    if (table != 'users') return CloudRow(table, row);
    return CloudRow(table, {
      for (final MapEntry(:key, :value) in row.entries)
        if (key != 'password_hash')
          key: key == 'role' && value == 'admin' ? 'supervisor' : value,
    });
  }

  // ── The snapshot ───────────────────────────────────────────────────────

  TableInfo<Table, Object?> _table(String name) =>
      _db.allTables.firstWhere((t) => t.actualTableName == name);

  static String _key(String table) => table == 'settings' ? 'key' : 'id';

  /// Row counts of every table the first upload sends, read together with
  /// the outbox's highest seq in one transaction.
  Future<({int maxSeq, int total})> snapshotStart() =>
      _db.transaction(() async {
        final seq = await maxSeq();
        var total = 0;
        for (final table in [...deskTables, ...ownerTables]) {
          total += await count(table);
        }
        return (maxSeq: seq, total: total);
      });

  Future<int> count(String table) async {
    final row = await _db
        .customSelect('SELECT count(*) AS n FROM "$table"')
        .getSingle();
    return row.read<int>('n');
  }

  /// Up to [limit] rows of [table] after key [after], in key order, as the
  /// cloud takes them.
  Future<List<CloudRow>> rowsAfter(
    String table,
    String? after, {
    required int limit,
  }) async {
    final info = _table(table);
    final key = _key(table);
    final rows = await _db
        .customSelect(
          'SELECT * FROM "$table" WHERE "$key" > ? ORDER BY "$key" LIMIT ?',
          variables: [
            Variable.withString(after ?? ''),
            Variable.withInt(limit),
          ],
          readsFrom: {info},
        )
        .get();
    return [
      for (final r in rows)
        cloudRow(
          table,
          (await info.map(r.data) as DataClass).toJson(
            serializer: auditJsonSerializer,
          ),
        ),
    ];
  }

  /// The key a [rowsAfter] page ended at.
  static String lastKey(List<CloudRow> page) =>
      page.last.row[_key(page.last.table)]! as String;

  /// Current prices: {category id: price}.
  Future<Map<String, int>> prices() async => {
    for (final c in await _db.select(_db.bedCategories).get())
      c.id: c.pricePerNight,
  };
}
