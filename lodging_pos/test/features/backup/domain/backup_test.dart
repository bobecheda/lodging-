import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/backup/domain/backup.dart';

void main() {
  group('file names', () {
    test('Nairobi time, minute precision, and back again', () {
      final at = nairobiInstant(2026, 10, 20, 7, 2);
      expect(backupFileName(at), 'lodging_pos-2026-10-20-0702.sqlite');
      expect(backupTakenAt('lodging_pos-2026-10-20-0702.sqlite'), at);
      // 23:30 Nairobi is 20:30 UTC: still the 20th.
      expect(
        backupFileName(nairobiInstant(2026, 10, 20, 23, 30)),
        'lodging_pos-2026-10-20-2330.sqlite',
      );
    });

    test('anything else in the folder is not a backup', () {
      for (final name in [
        'lodging_pos-2026-10-20-0702.sqlite.partial',
        'lodging_pos.sqlite',
        'lodging_pos-2026-10-20.sqlite',
        'notes.txt',
      ]) {
        expect(backupTakenAt(name), isNull, reason: name);
      }
    });

    test('the newest backup ignores other files', () {
      final newest = newestBackup([
        'lodging_pos-2026-10-19-1830.sqlite',
        'lodging_pos-2026-10-20-0702.sqlite',
        'lodging_pos-2026-10-21-0000.sqlite.partial',
        'readme.txt',
      ]);
      expect(newest?.name, 'lodging_pos-2026-10-20-0702.sqlite');
      expect(newestBackup(['readme.txt']), isNull);
    });
  });

  group('due', () {
    test('none yet → due', () {
      expect(
        isBackupDue(newest: null, now: nairobiInstant(2026, 10, 20, 7)),
        isTrue,
      );
    });

    test('by Nairobi day, not by 24 hours', () {
      final lastNight = nairobiInstant(2026, 10, 19, 23, 50);
      expect(
        isBackupDue(
          newest: lastNight,
          now: nairobiInstant(2026, 10, 19, 23, 59),
        ),
        isFalse,
      );
      // Ten minutes later it's a new day in Nairobi (21:00 UTC).
      expect(
        isBackupDue(newest: lastNight, now: nairobiInstant(2026, 10, 20, 0, 0)),
        isTrue,
      );
      expect(
        isBackupDue(
          newest: nairobiInstant(2026, 10, 20, 0, 1),
          now: nairobiInstant(2026, 10, 20, 23, 59),
        ),
        isFalse,
      );
    });
  });

  group('kept', () {
    String name(int month, int day, int hour) =>
        backupFileName(nairobiInstant(2026, month, day, hour));

    test('today and yesterday in full; then the latest of each day for 30 '
        'days; older ones go; other files are never touched', () {
      final now = nairobiInstant(2026, 11, 20, 9); // Fri 20 Nov
      final files = <String>[
        // Today and yesterday: three each, all kept.
        for (final h in [7, 12, 18]) name(11, 20, h),
        for (final h in [7, 12, 18]) name(11, 19, h),
        // 18 Nov to 22 Oct (days 3–30): three a day, the latest kept.
        for (var d = 0; d < 28; d++)
          for (final h in [7, 12, 18])
            backupFileName(addNairobiDays(nairobiInstant(2026, 11, 18, h), -d)),
        // 21 Oct and earlier: all go.
        name(10, 21, 18),
        name(10, 1, 7),
        'lodging_pos-2026-10-01-0700.sqlite.partial',
        'notes.txt',
      ];

      final stale = staleBackups(files, now);
      final kept = files.where((f) => !stale.contains(f)).toList();

      expect(kept, containsAll([name(11, 20, 7), name(11, 19, 7)]));
      expect(kept, contains(name(11, 18, 18)));
      expect(stale, containsAll([name(11, 18, 7), name(11, 18, 12)]));
      expect(kept, contains(name(10, 22, 18))); // day 30
      expect(stale, contains(name(10, 22, 12)));
      expect(stale, containsAll([name(10, 21, 18), name(10, 1, 7)]));
      expect(stale, isNot(contains('notes.txt')));
      expect(
        stale,
        isNot(contains('lodging_pos-2026-10-01-0700.sqlite.partial')),
      );
      // 6 (today, yesterday) + 28 (one a day) + 2 other files.
      expect(kept, hasLength(36));
    });

    test('nothing is deleted from an empty or young folder', () {
      final now = nairobiInstant(2026, 10, 20, 9);
      expect(staleBackups([], now), isEmpty);
      expect(staleBackups([name(10, 20, 7), name(10, 20, 8)], now), isEmpty);
    });

    test('a backup dated after today (the PC clock was wrong) is kept', () {
      final now = nairobiInstant(2026, 10, 20, 9);
      expect(staleBackups([name(12, 1, 7)], now), isEmpty);
    });
  });

  group('overdue', () {
    final now = nairobiInstant(2026, 10, 20, 9); // Tue

    test('a failed main backup is overdue at once', () {
      expect(
        backupOverdue(
          newest: nairobiInstant(2026, 10, 20, 7),
          lastFailed: true,
          now: now,
        ),
        isTrue,
      );
    });

    test('no backup for yesterday or today', () {
      bool overdue(DateTime newest) =>
          backupOverdue(newest: newest, lastFailed: false, now: now);
      expect(overdue(nairobiInstant(2026, 10, 20, 7)), isFalse); // today
      expect(overdue(nairobiInstant(2026, 10, 19, 0, 1)), isFalse); // Mon
      expect(overdue(nairobiInstant(2026, 10, 18, 23, 59)), isTrue); // Sun
    });

    test('before the first attempt there is nothing to say', () {
      expect(backupOverdue(newest: null, lastFailed: false, now: now), isFalse);
    });
  });

  test('sizes', () {
    expect(formatBackupSize(200), '1 KB');
    expect(formatBackupSize(640 * 1024), '640 KB');
    expect(formatBackupSize(1887437), '1.8 MB');
  });

  test('when, on the card; the chip’s words', () {
    final now = nairobiInstant(2026, 10, 20, 9); // Tue
    expect(
      formatBackupWhen(nairobiInstant(2026, 10, 20, 7, 2), now),
      'Today 07:02',
    );
    expect(
      formatBackupWhen(nairobiInstant(2026, 10, 19, 23, 50), now),
      'Yesterday 23:50',
    );
    expect(
      formatBackupWhen(nairobiInstant(2026, 10, 17, 7, 2), now),
      'Sat 17 Oct, 07:02',
    );
    expect(
      backupOverdueText(newest: nairobiInstant(2026, 10, 17, 7), failed: false),
      'Backup overdue · last Sat 17 Oct',
    );
    expect(
      backupOverdueText(newest: null, failed: true),
      'Backup failed · none yet',
    );
  });
}
