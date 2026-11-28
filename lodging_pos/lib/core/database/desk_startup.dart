import 'dart:async';

import '../app_version.dart';
import '../clock/nairobi.dart';

/// The desk's startup checks (docs/backup-restore.md, "Startup checks"):
/// pure rules over what the data folder holds, judged before the database
/// is opened for writing. The file work is in `database_files_native.dart`.

/// What a database file holds, for comparing it with the last backup.
/// Stays, payments and audit entries are never deleted (the triggers refuse
/// it), so none of these may ever go down on a desk.
final class DatabaseFigures {
  const DatabaseFigures({
    required this.schemaVersion,
    required this.stays,
    required this.payments,
    required this.auditEntries,
    required this.lastReceipt,
    required this.lastAuditAt,
  });

  factory DatabaseFigures.fromJson(Map<String, Object?> json) =>
      DatabaseFigures(
        schemaVersion: json['schema_version']! as int,
        stays: json['stays']! as int,
        payments: json['payments']! as int,
        auditEntries: json['audit_entries']! as int,
        lastReceipt: json['last_receipt'] as String?,
        lastAuditAt: switch (json['last_audit_at']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
      );

  final int schemaVersion;
  final int stays;
  final int payments;
  final int auditEntries;

  /// The highest receipt number taken (payments and refund payouts).
  final String? lastReceipt;

  /// When the newest audit entry was written (UTC).
  final DateTime? lastAuditAt;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'stays': stays,
    'payments': payments,
    'audit_entries': auditEntries,
    'last_receipt': lastReceipt,
    'last_audit_at': lastAuditAt?.toUtc().toIso8601String(),
  };

  /// "v11 · 30 stays · 46 payments · 711 audit entries · last receipt
  /// R-000050 · last entry Wed 11 Nov 11:03".
  String describe() => [
    'v$schemaVersion',
    '$stays stays',
    '$payments payments',
    '$auditEntries audit entries',
    'last receipt ${lastReceipt ?? 'none'}',
    'last entry ${switch (lastAuditAt) {
      final at? => formatDayDateTime(at),
      null => 'none',
    }}',
  ].join(' · ');

  /// Each figure at its highest of [a] and [b] (a mark never goes down).
  static DatabaseFigures highest(DatabaseFigures a, DatabaseFigures? b) {
    if (b == null) return a;
    int top(int x, int y) => x > y ? x : y;
    final (la, lb) = (a.lastAuditAt, b.lastAuditAt);
    return DatabaseFigures(
      schemaVersion: top(a.schemaVersion, b.schemaVersion),
      stays: top(a.stays, b.stays),
      payments: top(a.payments, b.payments),
      auditEntries: top(a.auditEntries, b.auditEntries),
      lastReceipt: receiptSerial(b.lastReceipt) > receiptSerial(a.lastReceipt)
          ? b.lastReceipt
          : a.lastReceipt,
      lastAuditAt: la == null || (lb != null && lb.isAfter(la)) ? lb : la,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DatabaseFigures &&
      other.schemaVersion == schemaVersion &&
      other.stays == stays &&
      other.payments == payments &&
      other.auditEntries == auditEntries &&
      other.lastReceipt == lastReceipt &&
      other.lastAuditAt == lastAuditAt;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    stays,
    payments,
    auditEntries,
    lastReceipt,
    lastAuditAt,
  );

  @override
  String toString() => describe();
}

/// The number in a receipt number (`R-000061` → 61), whatever its prefix;
/// 0 for none.
int receiptSerial(String? receipt) {
  if (receipt == null) return 0;
  final digits = RegExp(r'(\d+)$').firstMatch(receipt);
  return digits == null ? 0 : int.parse(digits[1]!);
}

/// The tables of the database [schema], through [scalar] (a query's first
/// column of its first row).
Future<Set<String>> tablesOf(
  FutureOr<Object?> Function(String query) scalar,
  String schema,
) async {
  final names = await scalar(
    "SELECT group_concat(name, ',') FROM \"$schema\".sqlite_master "
    "WHERE type = 'table'",
  );
  return {...?(names as String?)?.split(',')};
}

/// The figures of the database [schema] (`main`, or an attached backup
/// such as `backup_check`), through [scalar]: the live file read-only at
/// startup, or the backup service's checked copy.
Future<DatabaseFigures> figuresOf(
  FutureOr<Object?> Function(String query) scalar, {
  required String schema,
}) async {
  final tables = await tablesOf(scalar, schema);
  Future<int> count(String table) async => tables.contains(table)
      ? (await scalar('SELECT COUNT(*) FROM "$schema".$table'))! as int
      : 0;
  final receipts =
      [
          if (tables.contains('payments'))
            await scalar(
              'SELECT receipt_number FROM "$schema".payments '
              'ORDER BY created_at DESC LIMIT 1',
            ),
          if (tables.contains('refunds'))
            await scalar(
              'SELECT receipt_number FROM "$schema".refunds '
              'WHERE receipt_number IS NOT NULL ORDER BY paid_at DESC LIMIT 1',
            ),
        ].whereType<String>().toList()
        ..sort((a, b) => receiptSerial(b).compareTo(receiptSerial(a)));
  final lastAudit = tables.contains('audit_log')
      ? await scalar('SELECT MAX(created_at) FROM "$schema".audit_log')
      : null;
  return DatabaseFigures(
    schemaVersion: (await scalar('PRAGMA "$schema".user_version'))! as int,
    stays: await count('stays'),
    payments: await count('payments'),
    auditEntries: await count('audit_log'),
    lastReceipt: receipts.firstOrNull,
    lastAuditAt: switch (lastAudit) {
      final String at => DateTime.parse(at).toUtc(),
      final int seconds => DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ),
      _ => null,
    },
  );
}

/// An older backup the owner accepted as the live database, still to be
/// applied once it opens: the receipt counter raised to [counterFloor] and
/// `database.restore_accepted` audited.
final class PendingRestore {
  const PendingRestore({
    required this.acceptedBy,
    required this.acceptedAt,
    required this.counterFloor,
    required this.previous,
    this.cloudChecked = false,
  });

  factory PendingRestore.fromJson(Map<String, Object?> json) => PendingRestore(
    acceptedBy: json['accepted_by']! as String,
    acceptedAt: DateTime.parse(json['accepted_at']! as String),
    counterFloor: json['counter_floor']! as int,
    previous: DatabaseFigures.fromJson(
      (json['previous']! as Map).cast<String, Object?>(),
    ),
    cloudChecked: json['cloud_checked'] == true,
  );

  /// The cloud was checked first (a desk that has synced;
  /// story/restore-cloud-check).
  final bool cloudChecked;

  /// The owner's user id.
  final String acceptedBy;
  final DateTime acceptedAt;

  /// The next receipt number may not be lower than this.
  final int counterFloor;

  /// The mark the restored file was refused against.
  final DatabaseFigures previous;

  Map<String, Object?> toJson() => {
    'accepted_by': acceptedBy,
    'accepted_at': acceptedAt.toUtc().toIso8601String(),
    'counter_floor': counterFloor,
    'previous': previous.toJson(),
    'cloud_checked': cloudChecked,
  };
}

/// The operations after which the mark moves (story/desk-db-guards-2):
/// every receipt number issued, every shift opened or closed and every
/// drawer count.
const markActions = {
  'payment.create',
  'refund.pay',
  'shift.open',
  'shift.close',
  'drawer.start',
  'drawer.check',
  'drawer.collect',
};

/// Whether an operation that recorded [actions] moves the mark.
bool movesMark(Set<String> actions) => actions.any(markActions.contains);

/// The high-water mark (`lodging_pos.mark.json`, next to the database, and
/// a second copy outside the data folder): the most this desk has held.
/// Raised after every backup and, since story/desk-db-guards-2, after every
/// operation in [markActions]; the live file must never hold less.
final class HighWaterMark {
  const HighWaterMark({
    required this.backupName,
    required this.takenAt,
    required this.figures,
    required this.build,
    this.pendingRestore,
    DateTime? heldAt,
  }) : heldAt = heldAt ?? takenAt;

  /// [existing] raised to [live] at [at]: every figure at its highest, the
  /// last backup kept unless [backupName] is a new one, a pending restore
  /// kept.
  factory HighWaterMark.raised(
    HighWaterMark? existing,
    DatabaseFigures live, {
    required DateTime at,
    required DeskStamp build,
    String? backupName,
  }) => HighWaterMark(
    backupName: backupName ?? existing?.backupName,
    takenAt: backupName != null || existing == null ? at : existing.takenAt,
    figures: DatabaseFigures.highest(live, existing?.figures),
    build: build,
    pendingRestore: existing?.pendingRestore,
    heldAt: at,
  );

  factory HighWaterMark.fromJson(Map<String, Object?> json) => HighWaterMark(
    backupName: json['backup'] as String?,
    takenAt: DateTime.parse(json['taken_at']! as String),
    heldAt: switch (json['held_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    figures: DatabaseFigures.fromJson(
      (json['figures']! as Map).cast<String, Object?>(),
    ),
    build: DeskStamp(
      version: json['build_version']! as String,
      build: json['build']! as int,
    ),
    pendingRestore: switch (json['pending_restore']) {
      final Map<Object?, Object?> p => PendingRestore.fromJson(
        p.cast<String, Object?>(),
      ),
      _ => null,
    },
  );

  /// The last backup's file name; null before the first backup.
  final String? backupName;

  /// When the last backup was taken (or the mark first written).
  final DateTime takenAt;

  /// When the desk last held [figures].
  final DateTime heldAt;

  final DatabaseFigures figures;
  final DeskStamp build;
  final PendingRestore? pendingRestore;

  Map<String, Object?> toJson() => {
    'backup': backupName,
    'taken_at': takenAt.toUtc().toIso8601String(),
    'held_at': heldAt.toUtc().toIso8601String(),
    'figures': figures.toJson(),
    'build_version': build.version,
    'build': build.build,
    if (pendingRestore case final p?) 'pending_restore': p.toJson(),
  };

  HighWaterMark withoutPending() => HighWaterMark(
    backupName: backupName,
    takenAt: takenAt,
    figures: figures,
    build: build,
    heldAt: heldAt,
  );
}

/// Where the marks are kept (`MarkFiles`: the data folder and a second copy
/// outside it).
abstract interface class MarkStore {
  /// Raises both copies to [figures] (never lowers them); [backupName] when
  /// a backup was just taken.
  Future<void> raise(
    DatabaseFigures figures, {
    required DateTime at,
    String? backupName,
  });

  /// Writes [mark] as it is to both copies: an accepted restore lowers it
  /// on purpose.
  Future<void> replace(HighWaterMark mark);
}

/// No marks: where the desk has no data folder (web, tests).
final class NoMarks implements MarkStore {
  const NoMarks();

  @override
  Future<void> raise(
    DatabaseFigures figures, {
    required DateTime at,
    String? backupName,
  }) async {}

  @override
  Future<void> replace(HighWaterMark mark) async {}
}

/// The copy of the app holding the data folder's lock.
final class LockHolder {
  const LockHolder({
    required this.exePath,
    required this.version,
    required this.since,
  });

  factory LockHolder.fromJson(Map<String, Object?> json) => LockHolder(
    exePath: json['exe'] as String? ?? 'unknown',
    version: json['version'] as String? ?? 'unknown',
    since: json['since'] as String? ?? '',
  );

  final String exePath;

  /// "desk 1.0.0 (build 2)".
  final String version;

  /// When it started (UTC, ISO 8601).
  final String since;

  Map<String, Object?> toJson() => {
    'exe': exePath,
    'version': version,
    'since': since,
  };
}

/// The live database file as read at startup (read-only).
final class LiveFile {
  const LiveFile({
    required this.figures,
    this.stamp,
    this.installPath,
    this.everConnected = false,
    this.nextReceiptNumber = 1,
    this.deviceId,
    this.ownerEmail,
  });

  final DatabaseFigures figures;

  /// This install's device id (the `device` table): what the cloud's rows
  /// from this desk carry.
  final String? deviceId;

  /// The owner's cloud email as the file last knew it (`sync_state`
  /// `owner_email`); null if the file never connected.
  final String? ownerEmail;

  /// The highest build that opened it (`sync_state` `desk.build`); null
  /// before this story.
  final DeskStamp? stamp;

  /// The folder the desk was installed in (`desk.install_path`).
  final String? installPath;

  /// Whether this file was ever connected to the cloud.
  final bool everConnected;

  /// The receipt counter's next number on this device.
  final int nextReceiptNumber;
}

/// Everything the startup checks look at.
final class DeskInspection {
  const DeskInspection({
    this.live,
    this.hasBackups = false,
    this.mark,
    this.secondMark,
    this.heldBy,
  });

  /// Null when there is no `lodging_pos.sqlite`.
  final LiveFile? live;

  /// Daily backups, pre-upgrade copies or reset folders exist.
  final bool hasBackups;
  final HighWaterMark? mark;

  /// The mark's copy outside the data folder (`%LOCALAPPDATA%`): it stays
  /// put when someone copies the whole data folder back.
  final HighWaterMark? secondMark;

  /// Another copy of the app holds the lock.
  final LockHolder? heldBy;
}

/// The startup checks' outcome, made in `main()` before the database opens.
final class DeskStartup {
  const DeskStartup({
    this.folder,
    this.verdict = const StartOk(),
    this.inspection = const DeskInspection(),
    this.location = const LocationOk(),
  });

  /// Tests, web and the phone: no data folder, nothing to check.
  static const none = DeskStartup();

  /// The data folder; null where there is none.
  final String? folder;
  final StartupVerdict verdict;
  final DeskInspection inspection;
  final LocationCheck location;
}

/// What the startup checks decided.
sealed class StartupVerdict {
  const StartupVerdict();
}

/// Open the database and start the app.
final class StartOk extends StartupVerdict {
  const StartOk();
}

/// Another copy of the app has this data folder open.
final class AlreadyOpen extends StartupVerdict {
  const AlreadyOpen(this.holder);
  final LockHolder holder;
}

/// The live file is gone but backups show there was one: never a silent
/// first run.
final class DatabaseMissing extends StartupVerdict {
  const DatabaseMissing(this.mark);
  final HighWaterMark? mark;
}

/// The file's schema is newer than this build knows.
final class NewerDatabase extends StartupVerdict {
  const NewerDatabase(this.schemaVersion, this.stamp);
  final int schemaVersion;
  final DeskStamp? stamp;
}

/// A newer build has opened this file (same schema).
final class NewerBuild extends StartupVerdict {
  const NewerBuild(this.stamp);
  final DeskStamp stamp;
}

/// The live file holds less than the last backup: an older copy.
final class OlderThanBackup extends StartupVerdict {
  const OlderThanBackup(this.live, this.mark);
  final LiveFile live;
  final HighWaterMark mark;
}

/// The checks in order: the lock, a missing file, a newer schema, a newer
/// build, then the high-water mark.
StartupVerdict judgeStartup(
  DeskInspection inspection, {
  required AppBuild build,
  required int schemaVersion,
}) {
  if (inspection.heldBy case final holder?) return AlreadyOpen(holder);
  final live = inspection.live;
  if (live == null) {
    final mark = inspection.mark ?? inspection.secondMark;
    return inspection.hasBackups || mark != null
        ? DatabaseMissing(mark)
        : const StartOk();
  }
  if (live.figures.schemaVersion > schemaVersion) {
    return NewerDatabase(live.figures.schemaVersion, live.stamp);
  }
  if (live.stamp case final stamp? when stamp.build > build.build) {
    return NewerBuild(stamp);
  }
  for (final mark in [inspection.mark, inspection.secondMark].nonNulls) {
    if (isOlder(live.figures, mark.figures)) return OlderThanBackup(live, mark);
  }
  return const StartOk();
}

/// Whether [live] holds less than [mark] in any way.
bool isOlder(DatabaseFigures live, DatabaseFigures mark) =>
    live.schemaVersion < mark.schemaVersion ||
    live.stays < mark.stays ||
    live.payments < mark.payments ||
    live.auditEntries < mark.auditEntries ||
    receiptSerial(live.lastReceipt) < receiptSerial(mark.lastReceipt) ||
    switch ((live.lastAuditAt, mark.lastAuditAt)) {
      (null, _?) => true,
      (final l?, final m?) => l.isBefore(m),
      _ => false,
    };

/// The plain-words explanation of a refusal, naming both sides.
String refusalMessage(
  StartupVerdict verdict,
  AppBuild build, {
  required int schemaVersion,
}) {
  final self = 'This app is ${build.label}, database v$schemaVersion.';
  return switch (verdict) {
    StartOk() => '',
    AlreadyOpen(:final holder) =>
      'The desk is already open on this PC: ${holder.version}, from '
          '${holder.exePath}. $self',
    DatabaseMissing(:final mark) =>
      'The database file is missing, but backups show there was one'
          '${mark == null ? '' : ' (this desk last held, '
                    '${formatDayDateTime(mark.heldAt)}: '
                    '${mark.figures.describe()})'}. $self',
    NewerDatabase(schemaVersion: final v, :final stamp) =>
      'This database is v$v'
          '${stamp == null ? '' : ', last opened by ${stamp.label}'}. $self',
    NewerBuild(:final stamp) =>
      'This database was last opened by ${stamp.label}, a newer build. '
          '$self',
    OlderThanBackup(:final live, :final mark) =>
      'This database looks older than what this desk last held. This '
          'file: ${live.figures.describe()}. Last held '
          '(${formatDayDateTime(mark.heldAt)}, ${mark.build.label}'
          '${mark.backupName == null ? '' : '; last backup '
                    '${mark.backupName}'}): '
          '${mark.figures.describe()}. $self',
  };
}

/// Where the app runs from, against the recorded install folder.
sealed class LocationCheck {
  const LocationCheck();
}

final class LocationOk extends LocationCheck {
  const LocationOk();
}

/// The first run from a fixed drive: this folder becomes the install folder.
final class LocationRecord extends LocationCheck {
  const LocationRecord(this.path);
  final String path;
}

/// A removable drive, or another folder than the recorded one: a warning
/// the supervisor or owner may accept.
final class UnusualLocation extends LocationCheck {
  const UnusualLocation({
    required this.path,
    required this.removable,
    this.recorded,
  });

  final String path;
  final bool removable;
  final String? recorded;
}

/// Compares the folder of the running exe with the recorded one.
LocationCheck judgeLocation({
  required String exeFolder,
  required bool removable,
  required String? recorded,
}) {
  if (removable) {
    return UnusualLocation(
      path: exeFolder,
      removable: true,
      recorded: recorded,
    );
  }
  if (recorded == null) return LocationRecord(exeFolder);
  return samePath(exeFolder, recorded)
      ? const LocationOk()
      : UnusualLocation(path: exeFolder, removable: false, recorded: recorded);
}

/// Windows paths compare without case, separators or a trailing slash.
bool samePath(String a, String b) {
  String norm(String p) =>
      p.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();
  return norm(a) == norm(b);
}
