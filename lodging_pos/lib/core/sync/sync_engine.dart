import 'dart:async';
import 'dart:math';

import '../audit/audit_writer.dart';
import '../auth/user_account.dart';
import '../clock/clock.dart';
import '../database/database.dart';
import 'cloud.dart';
import 'cloud_writes.dart';
import 'desk_secret_store.dart';
import 'sync_store.dart';

enum SyncPhase {
  /// This build has no cloud settings (secrets.json): local only.
  notConfigured,

  /// The owner hasn't connected this desk yet.
  notConnected,

  /// The first upload is running.
  uploading,

  /// The first upload needs the owner signed in to finish.
  waitingForOwner,

  online,
  offline,

  /// Stopped at a refused row (or the desk's key): [SyncStatus.problem].
  problem,
}

final class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.lastSyncAt,
    this.uploadSent = 0,
    this.uploadTotal = 0,
    this.problem,
    this.needsReconnect = false,
  });

  final SyncPhase phase;

  /// The last time the cloud had everything this desk had written.
  final DateTime? lastSyncAt;
  final int uploadSent;
  final int uploadTotal;
  final String? problem;

  /// The desk's key is missing or refused: "Reconnect this desk".
  final bool needsReconnect;
}

/// Sync for this desk (sync-1, docs/sync.md): connecting, the resumable
/// first upload, the ordered push of the outbox, the heartbeat, and the
/// writes that go to the cloud first ([CloudWrites]).
///
/// With null intervals no timer runs; tests call [pushNow],
/// [continueFirstUpload] and [sendHeartbeat] themselves.
class SyncEngine implements CloudWrites {
  SyncEngine({
    required AppDatabase db,
    required this._audit,
    required this._cloud,
    required this._secrets,
    required this._clock,
    this.appVersion = '1.0.0',
    this.batchSize = 200,
    this.pushEvery,
    this.heartbeatEvery,
    this.nudgeDelay = const Duration(seconds: 2),
    Random? random,
  }) : _db = db,
       _store = SyncStore(db),
       _random = random ?? Random();

  final AppDatabase _db;
  final AuditWriter _audit;
  final Cloud _cloud;
  final DeskSecretStore _secrets;
  final Clock _clock;
  final SyncStore _store;
  final Random _random;

  final String appVersion;
  final int batchSize;
  final Duration? pushEvery;
  final Duration? heartbeatEvery;
  final Duration nudgeDelay;

  /// How long sent outbox rows are kept.
  static const keepSent = Duration(days: 30);
  static const _firstRetry = Duration(seconds: 5);
  static const _maxRetry = Duration(minutes: 5);

  final _changes = StreamController<SyncStatus>.broadcast();
  var _status = const SyncStatus(phase: SyncPhase.notConnected);

  late String _deviceId;
  var _connected = false;
  var _uploadDone = false;
  DateTime? _lastSyncAt;
  DateTime? _lastPushAt;

  Timer? _pushTimer;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  Timer? _nudgeTimer;
  var _failures = 0;
  DateTime? _retryAt;
  DateTime? _prunedAt;
  Future<void>? _pushing;
  Future<void>? _uploading;
  var _disposed = false;

  SyncStatus get status => _status;
  Stream<SyncStatus> get changes => _changes.stream;

  void _emit(SyncStatus status) {
    _status = status;
    if (!_disposed) _changes.add(status);
  }

  void _emitPhase(
    SyncPhase phase, {
    String? problem,
    bool needsReconnect = false,
    int? uploadSent,
    int? uploadTotal,
  }) => _emit(
    SyncStatus(
      phase: phase,
      lastSyncAt: _lastSyncAt,
      uploadSent: uploadSent ?? _status.uploadSent,
      uploadTotal: uploadTotal ?? _status.uploadTotal,
      problem: problem,
      needsReconnect: needsReconnect,
    ),
  );

  // ── Starting ───────────────────────────────────────────────────────────

  Future<void> start() async {
    _deviceId = await _db.deviceId();
    _connected = await _store.get(SyncStore.deskEmail) != null;
    _uploadDone = await _store.get(SyncStore.uploadDone) == 'yes';
    _lastPushAt = DateTime.tryParse(
      await _store.get(SyncStore.lastPushAt) ?? '',
    );
    _lastSyncAt = _lastPushAt;
    if (!_connected) {
      _emitPhase(SyncPhase.notConnected);
      return;
    }
    _startTimers();
    if (!await _ensureDesk()) return;
    await prune();
    if (_uploadDone) {
      await pushNow();
    } else {
      await continueFirstUpload();
    }
  }

  void _startTimers() {
    if (pushEvery case final every?) {
      _pushTimer ??= Timer.periodic(every, (_) => _tick());
    }
    if (heartbeatEvery case final every?) {
      _heartbeatTimer ??= Timer.periodic(every, (_) {
        unawaited(sendHeartbeat());
        unawaited(prune());
      });
    }
  }

  void _tick() {
    final due = _retryAt;
    if (due != null && _clock.now().isBefore(due)) return;
    unawaited(_uploadDone ? _push() : continueFirstUpload());
  }

  /// Signs the desk in from its stored key if it isn't yet. False (and the
  /// status says why) when it can't.
  Future<bool> _ensureDesk() async {
    if (_cloud.deskSignedIn) return true;
    final credentials = await _secrets.read();
    if (credentials == null) {
      _emitPhase(
        SyncPhase.problem,
        problem:
            'This desk’s cloud key is missing (is it signed in to Windows as '
            'another user?). The owner can reconnect this desk.',
        needsReconnect: true,
      );
      return false;
    }
    try {
      await _cloud.signInDesk(credentials);
      return true;
    } on CloudOffline {
      _offline();
      return false;
    } on CloudSignInRefused {
      _emitPhase(
        SyncPhase.problem,
        problem:
            'The cloud no longer accepts this desk’s key. The owner can '
            'reconnect this desk.',
        needsReconnect: true,
      );
      return false;
    }
  }

  // ── Connecting ─────────────────────────────────────────────────────────

  /// Connects this desk (the owner, at the desk, with a one-time install
  /// code), then starts the first upload. Throws [CloudOffline] or
  /// [CloudRefused] (the reason, for the owner).
  Future<void> connect({
    required UserAccount owner,
    required String installCode,
    required String ownerEmail,
    required String password,
  }) => _connect(
    owner: owner,
    installCode: installCode.trim().toUpperCase(),
    ownerEmail: ownerEmail,
    password: password,
  );

  /// "Reconnect this desk": the owner's cloud sign-in instead of a code,
  /// and a new key for this desk (e.g. its key was lost with a Windows
  /// user).
  Future<void> reconnect({
    required UserAccount owner,
    required String ownerEmail,
    required String password,
  }) => _connect(
    owner: owner,
    installCode: null,
    ownerEmail: ownerEmail,
    password: password,
  );

  Future<void> _connect({
    required UserAccount owner,
    required String? installCode,
    required String ownerEmail,
    required String password,
  }) async {
    final email = ownerEmail.trim().toLowerCase();
    final reconnecting = installCode == null;
    final credentials = await _cloud.connectDesk(
      ConnectRequest(
        reconnect: reconnecting,
        installCode: installCode,
        ownerEmail: email,
        ownerPassword: password,
        ownerUserId: owner.id,
        deviceId: _deviceId,
      ),
    );
    await _secrets.write(credentials);
    await _store.set(SyncStore.deskEmail, credentials.email);
    await _store.set(SyncStore.ownerEmail, email);
    await _store.set(SyncStore.problem, null);
    await _audit.recordEvent(
      action: reconnecting ? 'sync.reconnect' : 'sync.connect',
      userId: owner.id,
      entity: 'sync',
      entityId: _deviceId,
      details: {'owner_email': email},
    );
    _connected = true;
    _failures = 0;
    _retryAt = null;
    _startTimers();
    await _cloud.signInDesk(credentials);
    await _cloud.signInOwner(email, password);
    if (_uploadDone) {
      await pushNow();
    } else {
      await continueFirstUpload();
    }
  }

  // ── The owner at the desk ──────────────────────────────────────────────

  /// The owner signed in on the desk: signs them in to the cloud too (same
  /// password), quietly; offline or refused, their cloud writes will ask.
  Future<void> ownerSignedInOnDesk(String password) async {
    if (!_connected) return;
    final email = await _store.get(SyncStore.ownerEmail);
    if (email == null) return;
    try {
      await _cloud.signInOwner(email, password);
    } on Exception {
      return;
    }
    if (!_uploadDone) unawaited(continueFirstUpload());
  }

  /// The owner's password, asked for when a cloud write needs it. Throws
  /// [NeedsInternet] or [CloudSignInRefused].
  Future<void> signInOwner(String password) async {
    final email = await _store.get(SyncStore.ownerEmail);
    if (email == null) throw const CloudSignInRefused('Not connected.');
    try {
      await _cloud.signInOwner(email, password);
    } on CloudOffline {
      throw const NeedsInternet();
    }
    if (!_uploadDone) unawaited(continueFirstUpload());
  }

  /// The owner signed out or the screen locked.
  Future<void> ownerLeft() => _cloud.signOutOwner();

  // ── The first upload ───────────────────────────────────────────────────

  /// Starts or resumes the first upload: a snapshot of every synced table,
  /// parents first, each table from the last key sent (kept in
  /// `sync_state`, so a power cut resumes, never restarts). The desk sends
  /// its own tables; the owner's sign-in sends the earlier decisions and
  /// the prices and finishes it. Then the outbox rows the snapshot covered
  /// (up to the highest seq when it started) are marked sent; anything
  /// written since goes up through the normal push.
  Future<void> continueFirstUpload() =>
      _uploading ??= _firstUpload().whenComplete(() => _uploading = null);

  Future<void> _firstUpload() async {
    if (_uploadDone || !_connected) return;
    if (!await _ensureDesk()) return;
    if (await _store.get(SyncStore.uploadMaxSeq) == null) {
      final start = await _store.snapshotStart();
      await _store.set(SyncStore.uploadTotal, start.total);
      await _store.set(SyncStore.uploadSent, 0);
      await _store.set(SyncStore.uploadMaxSeq, start.maxSeq);
    }
    final maxSeq = await _store.getInt(SyncStore.uploadMaxSeq);
    final total = await _store.getInt(SyncStore.uploadTotal);
    var sent = await _store.getInt(SyncStore.uploadSent);
    _emitPhase(SyncPhase.uploading, uploadSent: sent, uploadTotal: total);
    try {
      for (final table in SyncStore.deskTables) {
        sent = await _uploadTable(table, sent, total, _cloud.importDeskRows);
      }
      if (!_cloud.ownerSignedIn) {
        _emitPhase(SyncPhase.waitingForOwner);
        return;
      }
      for (final table in SyncStore.ownerTables) {
        sent = await _uploadTable(
          table,
          sent,
          total,
          (rows) => _cloud.importOwnerRows(_deviceId, rows),
        );
      }
      await _cloud.setPrices(await _store.prices(), _clock.now());
      await _cloud.finishFirstUpload(_deviceId);
    } on CloudOffline {
      _offline();
      return;
    } on CloudSignInRefused {
      _emitPhase(SyncPhase.waitingForOwner);
      return;
    } on CloudRefused catch (e) {
      await _store.set(SyncStore.problem, e.message);
      _emitPhase(SyncPhase.problem, problem: e.message);
      _scheduleRetry();
      return;
    }
    final now = _clock.now();
    await _store.markSentUpTo(maxSeq, now);
    await _store.set(SyncStore.uploadDone, 'yes');
    await _store.set(SyncStore.problem, null);
    await _store.clear('upload.after.');
    _uploadDone = true;
    _lastSyncAt = now;
    await _audit.recordEvent(
      action: 'sync.first_upload',
      userId: null,
      entity: 'sync',
      entityId: _deviceId,
      details: {'rows': total},
    );
    _failures = 0;
    _retryAt = null;
    await pushNow();
  }

  Future<int> _uploadTable(
    String table,
    int sent,
    int total,
    Future<int> Function(List<CloudRow> rows) send,
  ) async {
    var after = await _store.get(SyncStore.uploadAfter(table));
    if (after == '*') return sent;
    while (true) {
      final page = await _store.rowsAfter(table, after, limit: batchSize);
      if (page.isEmpty) {
        await _store.set(SyncStore.uploadAfter(table), '*');
        return sent;
      }
      await send(page);
      after = SyncStore.lastKey(page);
      sent += page.length;
      await _store.set(SyncStore.uploadAfter(table), after);
      await _store.set(SyncStore.uploadSent, sent);
      _emitPhase(SyncPhase.uploading, uploadSent: min(sent, total));
    }
  }

  // ── Pushing ────────────────────────────────────────────────────────────

  /// After a write: push soon (a burst of writes goes up together). Off
  /// with the timers.
  void nudge() {
    if (pushEvery == null || !_connected || !_uploadDone) return;
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer(nudgeDelay, () => unawaited(_push()));
  }

  /// Pushes everything queued now ("Retry" too).
  Future<void> pushNow() {
    _retryAt = null;
    return _push();
  }

  Future<void> _push() =>
      _pushing ??= _pushLoop().whenComplete(() => _pushing = null);

  /// The outbox, oldest first, [batchSize] rows a call, each call all or
  /// nothing. A refused row stops the queue (order matters; nothing is
  /// skipped) until it goes through.
  Future<void> _pushLoop() async {
    if (!_connected || !_uploadDone || !await _ensureDesk()) return;
    while (true) {
      final batch = await _store.unsent(limit: batchSize);
      final now = _clock.now();
      if (batch.isEmpty) {
        _failures = 0;
        _retryAt = null;
        _lastSyncAt = now;
        await _store.set(SyncStore.problem, null);
        _emitPhase(SyncPhase.online);
        return;
      }
      try {
        await _cloud.pushChanges([
          for (final o in batch) SyncStore.fromOutbox(o),
        ]);
      } on CloudOffline {
        _offline();
        return;
      } on CloudSignInRefused {
        _cloud.deskSignedIn ? _offline() : await _ensureDesk();
        return;
      } on CloudRefused catch (e) {
        final row = batch[(e.index ?? 0).clamp(0, batch.length - 1)];
        await _store.recordFailure(row.seq, e.message);
        await _store.set(SyncStore.problem, e.message);
        _emitPhase(SyncPhase.problem, problem: e.message);
        _scheduleRetry();
        return;
      }
      await _store.markSent([for (final o in batch) o.seq], now);
      _lastPushAt = now;
      await _store.set(SyncStore.lastPushAt, now.toIso8601String());
    }
  }

  void _offline() {
    _emitPhase(SyncPhase.offline);
    _scheduleRetry();
  }

  /// 5 s, 10 s, 20 s … up to 5 min, with up to a second of jitter.
  void _scheduleRetry() {
    _failures++;
    final base = _firstRetry * pow(2, min(_failures - 1, 10)).toInt();
    final delay =
        (base > _maxRetry ? _maxRetry : base) +
        Duration(milliseconds: _random.nextInt(1000));
    _retryAt = _clock.now().add(delay);
    _retryTimer?.cancel();
    if (pushEvery == null) return;
    _retryTimer = Timer(delay, () {
      _retryAt = null;
      unawaited(_uploadDone ? _push() : continueFirstUpload());
    });
  }

  /// When the next retry is due, if one is waiting.
  DateTime? get retryAt => _retryAt;

  // ── Heartbeat and tidying ──────────────────────────────────────────────

  /// `desk_status` for the owner, whatever the queue is doing; failures
  /// are ignored (the next one tries again).
  Future<void> sendHeartbeat() async {
    if (!_connected || !await _ensureDesk()) return;
    try {
      await _cloud.heartbeat(
        DeskHeartbeat(
          pending: await _store.pendingCount(),
          lastPushAt: _lastPushAt,
          problem: _status.problem,
          appVersion: appVersion,
        ),
      );
    } on Exception {
      // Tried again in five minutes.
    }
  }

  /// Drops outbox rows sent more than [keepSent] ago, once a day.
  Future<void> prune() async {
    final now = _clock.now();
    final last = _prunedAt;
    if (last != null && now.difference(last) < const Duration(days: 1)) {
      return;
    }
    _prunedAt = now;
    await _store.pruneSent(now.subtract(keepSent));
  }

  // ── Writes that go to the cloud first ─────────────────────────────────

  @override
  bool get active => _connected;

  /// The owner is signed in to the cloud (decisions and prices can go).
  bool get ownerCloudSignedIn => _cloud.ownerSignedIn;

  /// The cloud has everything this desk wrote, and the owner is signed in
  /// when [owner]: the cloud-first write can go.
  Future<void> _readyForCloudWrite({required bool owner}) async {
    if (!_uploadDone) throw const FirstUploadUnfinished();
    if (owner && !_cloud.ownerSignedIn) throw const OwnerCloudSignInNeeded();
    if (!await _ensureDesk()) {
      throw _status.needsReconnect
          ? SyncBlocked(_status.problem ?? '')
          : const NeedsInternet();
    }
    await pushNow();
    switch (_status.phase) {
      case SyncPhase.offline:
        throw const NeedsInternet();
      case SyncPhase.problem:
        throw SyncBlocked(_status.problem ?? '');
      default:
        return;
    }
  }

  Future<CloudDecision> _call(Future<CloudDecision> Function() call) async {
    try {
      return await call();
    } on CloudOffline {
      throw const NeedsInternet();
    } on CloudSignInRefused {
      throw const OwnerCloudSignInNeeded();
    } on CloudRefused catch (e) {
      throw RefusedByCloud(e.message);
    }
  }

  static void _expectDecided(CloudDecision answer) {
    switch (answer) {
      case Decided():
        return;
      case AlreadyDecided(
        :final decision,
        :final decidedByName,
        :final decidedAt,
      ):
        throw DecidedElsewhere(
          approved: decision == 'approved',
          byName: decidedByName,
          at: decidedAt,
        );
      case AlreadyWithdrawn():
        throw const WithdrawnElsewhere();
      case StaleInCloud(:final currentPrice):
        throw StaleElsewhere(currentPrice);
      case MissingInCloud():
        throw const SyncBlocked(
          'This desk’s latest changes haven’t reached the cloud yet.',
        );
    }
  }

  @override
  Future<void> decideRefund({
    required String id,
    required String refundId,
    required bool approve,
    required String? note,
    required DateTime at,
  }) async {
    await _readyForCloudWrite(owner: true);
    _expectDecided(
      await _call(
        () => _cloud.decideRefund(
          id: id,
          refundId: refundId,
          decision: approve ? 'approved' : 'rejected',
          note: note,
          at: at,
          deviceId: _deviceId,
        ),
      ),
    );
  }

  @override
  Future<void> decidePriceRequest({
    required String id,
    required String requestId,
    required bool approve,
    required String? note,
    required DateTime at,
  }) async {
    await _readyForCloudWrite(owner: true);
    _expectDecided(
      await _call(
        () => _cloud.decidePriceRequest(
          id: id,
          requestId: requestId,
          decision: approve ? 'approved' : 'rejected',
          note: note,
          at: at,
          deviceId: _deviceId,
        ),
      ),
    );
  }

  @override
  Future<void> setPrices(Map<String, int> prices, DateTime at) async {
    await _readyForCloudWrite(owner: true);
    await _call(() async {
      await _cloud.setPrices(prices, at);
      return const Decided();
    });
  }

  @override
  Future<void> withdrawPriceRequest({
    required String requestId,
    required String by,
    required String? reason,
    required DateTime at,
  }) async {
    await _readyForCloudWrite(owner: false);
    _expectDecided(
      await _call(
        () => _cloud.withdrawPriceRequest(
          requestId: requestId,
          by: by,
          reason: reason,
          at: at,
        ),
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final t in [_pushTimer, _heartbeatTimer, _retryTimer, _nudgeTimer]) {
      t?.cancel();
    }
    await _changes.close();
    await _cloud.close();
  }
}
