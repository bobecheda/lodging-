import '../clock/nairobi.dart';
import '../database/desk_startup.dart' show receiptSerial;

/// "This desk's data is behind the cloud" (story/desk-db-guards-2,
/// docs/sync.md "Behind the cloud"): the cloud holds something from this
/// desk that the live file lacks, e.g. after an older copy replaced it.
/// Said only when the cloud proves it; pure rules.

/// What proved it.
enum BehindReason {
  /// The cloud has audit rows from this desk newer than its newest.
  newerRecords,

  /// The cloud has a receipt number from this desk above its last.
  higherReceipt,

  /// The cloud has an open shift from this desk that isn't in the file.
  unknownOpenShift,

  /// The push was refused: the cloud already has that receipt number.
  receiptTaken,

  /// The push was refused: the cloud already has an open shift from this
  /// desk.
  openShiftTaken,

  /// The pull brought a decision about something the file doesn't have.
  missingSubject,
}

/// The cloud's unique rules whose refusal proves it, by constraint name
/// (`supabase/migrations/20261023000000_tables.sql`; the pgTAP test
/// `desk_cloud_state_test.sql` checks they still exist).
const behindConstraints = {
  'payments_receipt_number_key': BehindReason.receiptTaken,
  'refunds_receipt_number_key': BehindReason.receiptTaken,
  'shifts_one_open_per_device': BehindReason.openShiftTaken,
};

/// What the cloud holds from this desk (`desk_cloud_state`), read with
/// the desk's own sign-in.
final class DeskCloudState {
  const DeskCloudState({
    this.newerAuditRows = 0,
    this.lastAuditAt,
    this.topReceipt,
    this.openShiftId,
  });

  /// This desk's audit rows newer than the desk's newest one.
  final int newerAuditRows;

  /// The newest of this desk's audit rows in the cloud.
  final DateTime? lastAuditAt;

  /// The highest receipt number from this desk (payments, refund payouts).
  final String? topReceipt;

  /// This desk's open shift in the cloud, if any.
  final String? openShiftId;
}

/// What the live file holds, to compare.
final class DeskHere {
  const DeskHere({
    required this.lastOwnAuditAt,
    required this.nextReceiptNumber,
    required this.openShiftKnown,
    this.lastReceipt,
  });

  /// The last receipt number issued here, as printed (for the details).
  final String? lastReceipt;

  /// The newest audit row this desk wrote itself (pulled rows from the
  /// phone don't count).
  final DateTime? lastOwnAuditAt;

  /// The receipt counter's next number.
  final int nextReceiptNumber;

  /// Whether the cloud's open shift is a shift in this file, in any state
  /// (a close not sent yet leaves it open in the cloud).
  final bool openShiftKnown;
}

/// What the cloud proved, kept on the desk (`sync_state` `behind`) until
/// the data folder is replaced, and audited `desk.behind_cloud`.
final class BehindEvidence {
  const BehindEvidence({
    required this.reasons,
    required this.foundAt,
    this.newerAuditRows = 0,
    this.cloudLastAuditAt,
    this.cloudTopReceipt,
    this.cloudOpenShiftId,
    this.deskLastAuditAt,
    this.deskLastReceipt,
    this.detail,
  });

  factory BehindEvidence.fromJson(Map<String, Object?> json) => BehindEvidence(
    reasons: [
      for (final r in json['reasons']! as List)
        BehindReason.values.byName(r as String),
    ],
    foundAt: DateTime.parse(json['found_at']! as String),
    newerAuditRows: json['newer_audit_rows'] as int? ?? 0,
    cloudLastAuditAt: _time(json['cloud_last_audit_at']),
    cloudTopReceipt: json['cloud_top_receipt'] as String?,
    cloudOpenShiftId: json['cloud_open_shift'] as String?,
    deskLastAuditAt: _time(json['desk_last_audit_at']),
    deskLastReceipt: json['desk_last_receipt'] as String?,
    detail: json['detail'] as String?,
  );

  final List<BehindReason> reasons;
  final DateTime foundAt;
  final int newerAuditRows;
  final DateTime? cloudLastAuditAt;
  final String? cloudTopReceipt;
  final String? cloudOpenShiftId;
  final DateTime? deskLastAuditAt;
  final String? deskLastReceipt;

  /// The refused receipt number, or what a pulled decision was about.
  final String? detail;

  Map<String, Object?> toJson() => {
    'reasons': [for (final r in reasons) r.name],
    'found_at': foundAt.toUtc().toIso8601String(),
    'newer_audit_rows': newerAuditRows,
    'cloud_last_audit_at': cloudLastAuditAt?.toUtc().toIso8601String(),
    'cloud_top_receipt': cloudTopReceipt,
    'cloud_open_shift': cloudOpenShiftId,
    'desk_last_audit_at': deskLastAuditAt?.toUtc().toIso8601String(),
    'desk_last_receipt': deskLastReceipt,
    'detail': detail,
  };

  /// The owner's details, one plain line per proof.
  List<String> lines() => [for (final r in reasons) _line(r)];

  String _line(BehindReason reason) => switch (reason) {
    BehindReason.newerRecords =>
      'The cloud has $newerAuditRows records from this desk newer than this '
          'PC’s last one (cloud: ${_when(cloudLastAuditAt)}; this PC: '
          '${_when(deskLastAuditAt)}).',
    BehindReason.higherReceipt =>
      'The cloud has receipt $cloudTopReceipt from this desk; this PC’s '
          'last is ${deskLastReceipt ?? 'none'}.',
    BehindReason.unknownOpenShift =>
      'The cloud has an open shift from this desk '
          '(${_short(cloudOpenShiftId)}) that this PC doesn’t have.',
    BehindReason.receiptTaken =>
      'The cloud already has receipt ${detail ?? 'number'} from this desk.',
    BehindReason.openShiftTaken =>
      'The cloud already has an open shift from this desk.',
    BehindReason.missingSubject =>
      'The cloud has $detail, which this PC doesn’t have.',
  };
}

DateTime? _time(Object? v) => v is String ? DateTime.parse(v).toUtc() : null;

String _when(DateTime? at) => at == null ? 'none' : formatDayDateTime(at);

String _short(String? id) =>
    id == null ? '?' : (id.length > 8 ? id.substring(0, 8) : id);

/// "R-000050" for the counter's [next] 51, when the file's own last
/// receipt isn't given; null before the first receipt.
String? _lastIssued(int next) =>
    next <= 1 ? null : 'R-${(next - 1).toString().padLeft(6, '0')}';

/// Behind if the cloud proves it: records from this desk newer than the
/// file's newest, a receipt number above the last one issued here, or an
/// open shift the file doesn't have. Rows the desk hasn't sent yet never
/// count (the desk is ahead, not behind).
BehindEvidence? deskBehind(
  DeskHere here,
  DeskCloudState cloud, {
  required DateTime now,
}) {
  final issued = here.nextReceiptNumber - 1;
  final reasons = [
    if (cloud.newerAuditRows > 0) BehindReason.newerRecords,
    if (receiptSerial(cloud.topReceipt) > issued) BehindReason.higherReceipt,
    if (cloud.openShiftId != null && !here.openShiftKnown)
      BehindReason.unknownOpenShift,
  ];
  if (reasons.isEmpty) return null;
  return BehindEvidence(
    reasons: reasons,
    foundAt: now,
    newerAuditRows: cloud.newerAuditRows,
    cloudLastAuditAt: cloud.lastAuditAt,
    cloudTopReceipt: cloud.topReceipt,
    cloudOpenShiftId: cloud.openShiftId,
    deskLastAuditAt: here.lastOwnAuditAt,
    deskLastReceipt: here.lastReceipt ?? _lastIssued(here.nextReceiptNumber),
  );
}

/// Behind if the cloud refused a pushed row on one of
/// [behindConstraints]; null for any other refusal. [detail]: the
/// refused receipt number, when there is one.
BehindEvidence? behindFromRefusal(
  String message, {
  String? detail,
  required DateTime now,
}) {
  for (final MapEntry(key: constraint, value: reason)
      in behindConstraints.entries) {
    if (message.contains('"$constraint"')) {
      return BehindEvidence(reasons: [reason], foundAt: now, detail: detail);
    }
  }
  return null;
}

/// Behind: the pull brought [what] (e.g. "a review of shift 37441d06")
/// about something the file doesn't have.
BehindEvidence behindFromMissing(String what, {required DateTime now}) =>
    BehindEvidence(
      reasons: const [BehindReason.missingSubject],
      foundAt: now,
      detail: what,
    );
