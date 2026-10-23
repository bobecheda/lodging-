/// What this desk asks of the cloud (supabase/migrations, docs/sync.md).
/// `SupabaseCloud` talks to Supabase; tests use `FakeCloud`, which keeps
/// the same rules.
///
/// Two sign-ins: the desk's own (a device account, used for everything the
/// desk writes) and, while the owner is at the desk, the owner's (decisions
/// and prices, which are the owner's to write).
library;

/// One synced row as the cloud takes it: the table and the row's columns
/// (snake_case, times as ISO-8601 UTC strings).
final class CloudRow {
  const CloudRow(this.table, this.row);

  final String table;
  final Map<String, Object?> row;

  Map<String, Object?> toJson() => {'table': table, 'row': row};
}

/// The desk's cloud sign-in, from connect-desk. The secret lives only in
/// the Windows user's protected storage.
final class DeskCredentials {
  const DeskCredentials({required this.email, required this.secret});

  final String email;
  final String secret;
}

/// What connect-desk needs.
final class ConnectRequest {
  const ConnectRequest({
    required this.reconnect,
    required this.installCode,
    required this.ownerEmail,
    required this.ownerPassword,
    required this.ownerUserId,
    required this.deviceId,
  });

  /// "Reconnect this desk": the owner's sign-in stands in for a code.
  final bool reconnect;
  final String? installCode;
  final String ownerEmail;
  final String ownerPassword;
  final String ownerUserId;
  final String deviceId;
}

/// The desk's heartbeat (`desk_status`), every ~5 minutes.
final class DeskHeartbeat {
  const DeskHeartbeat({
    required this.pending,
    required this.lastPushAt,
    required this.problem,
    required this.appVersion,
  });

  final int pending;
  final DateTime? lastPushAt;
  final String? problem;
  final String appVersion;
}

/// The answer to an owner decision or a withdrawal.
sealed class CloudDecision {
  const CloudDecision();
}

/// Written (or this same decision was written already: a retry).
final class Decided extends CloudDecision {
  const Decided();
}

/// Someone decided first; the first decision stands.
final class AlreadyDecided extends CloudDecision {
  const AlreadyDecided({
    required this.decision,
    required this.decidedByName,
    required this.decidedAt,
  });

  /// `approved` or `rejected`.
  final String decision;
  final String? decidedByName;
  final DateTime decidedAt;
}

/// The price request was withdrawn first.
final class AlreadyWithdrawn extends CloudDecision {
  const AlreadyWithdrawn();
}

/// The category's price in the cloud is no longer the one asked against.
final class StaleInCloud extends CloudDecision {
  const StaleInCloud(this.currentPrice);
  final int currentPrice;
}

/// The row being decided isn't in the cloud (its push hasn't arrived).
final class MissingInCloud extends CloudDecision {
  const MissingInCloud();
}

/// The cloud can't be reached: no internet, a timeout, the server down.
/// The work waits and is tried again.
final class CloudOffline implements Exception {
  const CloudOffline([this.reason]);
  final String? reason;

  @override
  String toString() => 'Offline${reason == null ? '' : ': $reason'}';
}

/// The cloud refused the request: a rule, a check, a permission. Trying
/// again won't help until something changes. [index] is the refused row's
/// position in the batch, when the cloud names one.
final class CloudRefused implements Exception {
  const CloudRefused(this.message, {this.index});
  final String message;
  final int? index;

  @override
  String toString() => message;
}

/// A sign-in was refused: wrong email or password, or a missing account.
final class CloudSignInRefused implements Exception {
  const CloudSignInRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class Cloud {
  /// connect-desk (connect or reconnect). Throws [CloudOffline] or
  /// [CloudRefused] (with the owner-facing reason).
  Future<DeskCredentials> connectDesk(ConnectRequest request);

  // ── The desk's sign-in ─────────────────────────────────────────────────

  Future<void> signInDesk(DeskCredentials credentials);
  bool get deskSignedIn;
  Future<bool> firstUploadDone();

  /// The first upload, desk part (a snapshot; batches may repeat).
  Future<int> importDeskRows(List<CloudRow> rows);

  /// The outbox, in order, all or nothing per call.
  Future<int> pushChanges(List<CloudRow> rows);

  Future<CloudDecision> withdrawPriceRequest({
    required String requestId,
    required String by,
    required String? reason,
    required DateTime at,
  });

  Future<void> heartbeat(DeskHeartbeat heartbeat);

  // ── The owner's sign-in ────────────────────────────────────────────────

  Future<void> signInOwner(String email, String password);
  bool get ownerSignedIn;
  Future<void> signOutOwner();

  /// The first upload, owner part: decisions made before connecting.
  Future<int> importOwnerRows(String deviceId, List<CloudRow> rows);
  Future<void> finishFirstUpload(String deviceId);

  /// {category id: price}.
  Future<void> setPrices(Map<String, int> prices, DateTime at);

  Future<CloudDecision> decideRefund({
    required String id,
    required String refundId,
    required String decision,
    required String? note,
    required DateTime at,
    required String deviceId,
  });

  Future<CloudDecision> decidePriceRequest({
    required String id,
    required String requestId,
    required String decision,
    required String? note,
    required DateTime at,
    required String deviceId,
  });

  /// Lets go of both sign-ins and the connections.
  Future<void> close();
}
