import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The single write path (CLAUDE.md): every write goes through
/// `AuditWriter.writeWithAudit`, so it gets its audit and outbox rows. The
/// only other writers allowed are listed here, each for a reason:
///
/// - `core/audit/audit_writer.dart`: the write path itself.
/// - `core/database/`: creating, seeding and upgrading the database.
/// - `features/backup/data/backup_service.dart`: `VACUUM INTO` and the
///   check of the copy, which change no rows.
/// - `core/sync/sync_store.dart`: sync's own bookkeeping, the local-only
///   `sync_state` and `outbox` tables and nothing else.
/// - `core/sync/pulled_rows.dart`: **the one exception for synced
///   tables**, rows the pull brings from the owner's side (they come with
///   their own audit rows and are never pushed back).
void main() {
  final writes = RegExp(
    r'\.into\(|\b_?db\s*\.\s*(update|delete)\(|customUpdate\(|customInsert\('
    r'|insertOnConflictUpdate|\.batch\(|customStatement\(',
  );

  List<File> dartFiles() => [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('.steps.dart'))
        f,
  ];

  String rel(File f) => f.path.replaceAll(r'\', '/');

  test('only the listed files write to the database', () {
    const allowed = [
      'lib/core/audit/audit_writer.dart',
      'lib/core/database/',
      'lib/features/backup/data/backup_service.dart',
      'lib/core/sync/sync_store.dart',
      'lib/core/sync/pulled_rows.dart',
    ];
    final writers = [
      for (final f in dartFiles())
        if (writes.hasMatch(f.readAsStringSync())) rel(f),
    ];
    final strays = [
      for (final w in writers)
        if (!allowed.any(w.startsWith)) w,
    ];
    expect(strays, isEmpty, reason: 'write through writeWithAudit instead');
    expect(writers, contains('lib/core/sync/pulled_rows.dart'));
  });

  test('sync_store.dart writes only sync_state and the outbox', () {
    final src = File('lib/core/sync/sync_store.dart').readAsStringSync();
    final tables = {
      for (final m in RegExp(
        r'(?:into|update|delete)\(\s*_db\.(\w+)',
      ).allMatches(src))
        m.group(1)!,
    };
    expect(tables, {'syncState', 'outbox'});
    for (final m in RegExp(r"customUpdate\(\s*'([^']*)'").allMatches(src)) {
      expect(m.group(1), startsWith('UPDATE outbox '));
    }
  });

  test('the backup changes no rows', () {
    final src = File('lib/features/backup/data/backup_service.dart')
        .readAsStringSync();
    for (final m in RegExp(r"customStatement\(\s*'([^']*)'").allMatches(src)) {
      expect(
        m.group(1)!.toUpperCase(),
        isNot(matches(RegExp(r'\b(INSERT|UPDATE|DELETE|REPLACE)\b'))),
      );
    }
    expect(src, isNot(matches(RegExp(r'\.into\(|\b_?db\.(update|delete)\('))));
  });
}
