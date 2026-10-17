import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../clock/clock.dart';
import 'database.dart';
import 'database_provider.dart';
import 'test_database_file.dart';

part 'schema_check.g.dart';

/// After opening (and any migration), the database file's tables, indexes or
/// triggers still differ from what this build creates: a file made by a
/// development build, or a migration that went wrong. Every schema change is
/// a migration with a test, so on a real install this should never fire.
final class SchemaDrift {
  const SchemaDrift(this.differences);

  /// e.g. `Changed: table bed_categories`, `Missing: table refunds`.
  final List<String> differences;
}

/// Compares every table, index and trigger in [live] with [expected] (a
/// fresh database from this build). Empty when they match.
Future<List<String>> schemaDifferences(
  GeneratedDatabase live,
  GeneratedDatabase expected,
) async {
  final have = await _objects(live);
  final want = await _objects(expected);
  return [
    for (final MapEntry(:key, :value) in want.entries)
      if (!have.containsKey(key))
        'Missing: $key'
      else if (have[key] != value)
        'Changed: $key',
    for (final key in have.keys)
      if (!want.containsKey(key)) 'Not expected: $key',
  ];
}

/// [sql] in one spelling: whitespace runs collapsed to one space, `"`
/// identifier quotes stripped, and no space next to `(`, `)` or `,`.
///
/// A table a migration rebuilt from its frozen version (`alterTable`) is
/// written as `CHECK (kind IN …)` and `REFERENCES stays(id)` where a fresh
/// file has `CHECK("kind" IN …)` and `REFERENCES stays (id)`: the same
/// schema in other words. Words stay apart, so any real difference (a
/// column, a type, a constraint) still counts. If text comparison causes
/// trouble again, compare `PRAGMA table_info` / `index_list` /
/// `foreign_key_list` instead (owner's decision, 17 Oct 2026).
String normalizeSchemaSql(String sql) => sql
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll('"', '')
    .replaceAll(RegExp(r' ?([(),]) ?'), r'$1')
    .trim();

/// `type name` → its SQL, normalized ([normalizeSchemaSql]).
Future<Map<String, String>> _objects(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT type, name, sql FROM sqlite_master '
        "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
      )
      .get();
  return {
    for (final r in rows)
      '${r.read<String>('type')} ${r.read<String>('name')}': normalizeSchemaSql(
        r.readNullable<String>('sql') ?? '',
      ),
  };
}

/// Null when the database file matches this build (always null on web,
/// which has no local database).
@Riverpod(keepAlive: true)
Future<SchemaDrift?> schemaDrift(Ref ref) async {
  final live = ref.watch(appDatabaseProvider);
  final executor = inMemoryExecutor();
  if (executor == null) return null;
  // A second AppDatabase on purpose, on its own in-memory executor: drift's
  // "created multiple times" warning doesn't apply, so it's off while this
  // one is made.
  final warn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final AppDatabase expected;
  try {
    expected = AppDatabase(executor, clock: ref.watch(clockProvider));
  } finally {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = warn;
  }
  try {
    final differences = await schemaDifferences(live, expected);
    return differences.isEmpty ? null : SchemaDrift(differences);
  } finally {
    await expected.close();
  }
}

/// Whether the mismatch screen may offer a reset: debug builds only. A
/// release build never throws data away; it shows an error instead.
@Riverpod(keepAlive: true)
bool canResetDatabase(Ref ref) => kDebugMode;

/// Closes the database, renames its file to a timestamped `.bak` next to it
/// (kept, not deleted) and reopens a fresh one. Returns the backup's path.
/// Overridden in tests, which use in-memory databases.
@Riverpod(keepAlive: true)
Future<String> Function() resetTestDatabase(Ref ref) => () async {
  await ref.read(appDatabaseProvider).close();
  final backup = await backUpDatabaseFile(ref.read(clockProvider).now());
  // Only now, with the old file moved away, may a new database open.
  ref.invalidate(appDatabaseProvider);
  return backup;
};
