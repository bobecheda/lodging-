import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every operation on the live database file and the files beside it
/// (`lodging_pos.sqlite*`, the mark, the lock) lives in one place,
/// `lib/core/database/database_files_native.dart` (story/desk-db-guards).
/// Nothing else may rename, copy or delete files, except the backups
/// (their own folder) and saved receipts (PDFs), and nothing else may name
/// the live file.
void main() {
  const onePlace = 'lib/core/database/database_files_native.dart';

  /// Files that may change files on disk, each for a reason.
  const fileWriters = {
    onePlace,
    // The daily backups, in their own folder; never the live file.
    'lib/features/backup/data/backup_files_native.dart',
    // Receipt PDFs saved to Documents.
    'lib/features/receipts/presentation/receipt_files_native.dart',
  };

  final mutations = RegExp(
    r'\.(rename|renameSync|copy|copySync|delete|deleteSync|writeAsBytes|'
    r'writeAsBytesSync|writeAsString|writeAsStringSync|openWrite|truncate|'
    r'truncateSync|createSync|create)\(',
  );
  final liveNames = RegExp(
    r'lodging_pos\.sqlite|databaseFileName|markFileName|lockFileName|'
    r'databaseFilePath\(|\$databaseName\.',
  );

  /// The library's Dart files, generated code left out, with `//` comment
  /// lines removed.
  Map<String, String> sources() => {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('database.steps.dart'))
        f.path.replaceAll(r'\', '/'): f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'),
  };

  test('only the one place names the live file and the files beside it', () {
    final offenders = [
      for (final MapEntry(:key, :value) in sources().entries)
        if (key != onePlace && liveNames.hasMatch(value)) key,
    ];
    expect(offenders, isEmpty, reason: 'go through $onePlace');
  });

  test('only the listed files rename, copy or delete files', () {
    final offenders = [
      for (final MapEntry(:key, :value) in sources().entries)
        if (value.contains("import 'dart:io'") &&
            !fileWriters.contains(key) &&
            mutations.hasMatch(value))
          key,
    ];
    expect(offenders, isEmpty);
  });

  test('VACUUM INTO only writes pre-upgrade copies and daily backups', () {
    final offenders = [
      for (final MapEntry(:key, :value) in sources().entries)
        if (value.contains('VACUUM INTO') &&
            key != onePlace &&
            key != 'lib/features/backup/data/backup_service.dart')
          key,
    ];
    expect(offenders, isEmpty);
  });

  test('the backups never name the live file', () {
    final backups =
        sources()['lib/features/backup/data/backup_files_native.dart']!;
    expect(liveNames.hasMatch(backups), isFalse);
  });
}
