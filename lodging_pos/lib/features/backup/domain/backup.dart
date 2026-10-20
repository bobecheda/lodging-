import '../../../core/clock/nairobi.dart';

/// Daily local backups of the desk database: what they're called, when one
/// is due, which to keep and when the desk should warn. Pure rules; the
/// copying is in `data/backup_service.dart`.

/// Backup file names start with this: `lodging_pos-2026-10-20-0702.sqlite`.
const backupFilePrefix = 'lodging_pos-';

/// How many Nairobi days of backups are kept (the latest of each day).
const backupKeepDays = 30;

/// `lodging_pos-YYYY-MM-DD-HHMM.sqlite`, in Nairobi time, for a backup taken
/// at [utc]. Two backups in the same minute share a name; the later wins.
String backupFileName(DateTime utc) {
  final t = toNairobi(utc);
  String two(int n) => n.toString().padLeft(2, '0');
  return '$backupFilePrefix${t.year}-${two(t.month)}-${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}.sqlite';
}

final _namePattern = RegExp(
  r'^lodging_pos-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})\.sqlite$',
);

/// When the backup called [name] was taken (UTC), or null if [name] isn't a
/// backup file (e.g. a `.partial` copy or something else in the folder).
DateTime? backupTakenAt(String name) {
  final m = _namePattern.firstMatch(name);
  if (m == null) return null;
  final [year, month, day, hour, minute] = [
    for (var i = 1; i <= 5; i++) int.parse(m[i]!),
  ];
  return nairobiInstant(year, month, day, hour, minute);
}

/// The Nairobi calendar date of [utc], as a UTC midnight to compare by.
DateTime _day(DateTime utc) {
  final t = toNairobi(utc);
  return DateTime.utc(t.year, t.month, t.day);
}

/// The newest backup among [names], or null if there is none.
({String name, DateTime takenAt})? newestBackup(Iterable<String> names) {
  ({String name, DateTime takenAt})? newest;
  for (final name in names) {
    final at = backupTakenAt(name);
    if (at != null && (newest == null || at.isAfter(newest.takenAt))) {
      newest = (name: name, takenAt: at);
    }
  }
  return newest;
}

/// Whether the daily backup is still to be taken: none yet, or the newest
/// is from an earlier Nairobi day than [now].
bool isBackupDue({required DateTime? newest, required DateTime now}) =>
    newest == null || _day(newest).isBefore(_day(now));

/// Of [names] (the files in a backup folder), the backups to delete at
/// [now]: every backup from today and yesterday is kept, and for the
/// [keepDays] Nairobi days up to today, the latest of each day. Anything
/// older goes. Files that aren't backups are never touched.
List<String> staleBackups(
  Iterable<String> names,
  DateTime now, {
  int keepDays = backupKeepDays,
}) {
  final today = _day(now);
  final yesterday = _day(addNairobiDays(now, -1));
  final oldestKept = _day(addNairobiDays(now, -(keepDays - 1)));
  final latestOfDay = <DateTime, ({String name, DateTime at})>{};
  final backups = <({String name, DateTime at, DateTime day})>[];
  for (final name in names) {
    final at = backupTakenAt(name);
    if (at == null) continue;
    final day = _day(at);
    backups.add((name: name, at: at, day: day));
    final latest = latestOfDay[day];
    if (latest == null || at.isAfter(latest.at)) {
      latestOfDay[day] = (name: name, at: at);
    }
  }
  bool kept(({String name, DateTime at, DateTime day}) b) {
    if (b.day == today || b.day == yesterday) return true;
    // A backup "from the future" (the PC clock was wrong) is kept too.
    if (b.day.isAfter(today)) return true;
    if (b.day.isBefore(oldestKept)) return false;
    return latestOfDay[b.day]!.name == b.name;
  }

  return [
    for (final b in backups)
      if (!kept(b)) b.name,
  ]..sort();
}

/// Whether the sidebar warns that backups are overdue: the last main
/// backup failed, or the newest one is older than yesterday (Nairobi
/// days). Before the first attempt ([newest] null and nothing failed)
/// there is nothing to say yet. A skipped or failed second copy never
/// counts: the Backups card mentions it quietly.
bool backupOverdue({
  required DateTime? newest,
  required bool lastFailed,
  required DateTime now,
}) {
  if (lastFailed) return true;
  if (newest == null) return false;
  return _day(newest).isBefore(_day(addNairobiDays(now, -1)));
}

/// `640 KB`, `1.8 MB`: a backup's size for the Backups card.
String formatBackupSize(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes < mb) {
    final k = (bytes / kb).ceil();
    return '${k < 1 ? 1 : k} KB';
  }
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}

/// `Today 07:02`, `Yesterday 18:30`, else `Sat 17 Oct, 07:02`: when a
/// backup was taken, as the Backups card says it.
String formatBackupWhen(DateTime takenAt, DateTime now) {
  final day = _day(takenAt);
  if (day == _day(now)) return 'Today ${formatTime(takenAt)}';
  if (day == _day(addNairobiDays(now, -1))) {
    return 'Yesterday ${formatTime(takenAt)}';
  }
  return formatDayDateComma(takenAt);
}

/// The sidebar chip's words for [overdue] backups: the last good one, if
/// any.
String backupOverdueText({required DateTime? newest, required bool failed}) {
  final last = newest == null ? 'none yet' : 'last ${formatDayDate(newest)}';
  return failed ? 'Backup failed · $last' : 'Backup overdue · $last';
}
