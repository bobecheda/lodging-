import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../audit/audit_writer.dart';
import '../auth/owner_password.dart';
import '../auth/user_account.dart';
import '../clock/clock.dart';
import '../database/database.dart';
import 'cloud.dart';
import 'cloud_writes.dart';
import 'desk_secret_store.dart';
import 'pulled_rows.dart';
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
    this.clockOffset,
    this.clockWarning = false,
  });

  final SyncPhase phase;

  /// The last time the cloud had everything this desk had written.
  final DateTime? lastSyncAt;
  final int uploadSent;
  final int uploadTotal;
  final String? problem;

  /// The desk's key is missing or refused: "Reconnect this desk".
  final bool needsReconnect;

  /// The PC's clock minus the server's, from the last pull (sync-2).
  final Duration? clockOffset;

  /// The PC's clock is more than 5 minutes off (until it's back within 4).
  final bool clockWarning;
}

/// Sync for this desk (docs/sync.md): connecting, the resumable first
/// upload, the ordered push of the outbox, the heartbeat, the writes that go
/// to the cloud first ([CloudWrites]) and, since sync-2, the pull of what the
/// owner's side wrote and the clock check.
///
/// With null intervals no timer runs; tests call [syncNow], [pushNow],
/// [pullNow], [continueFirstUpload] and [sendHeartbeat] themselves.
class SyncEngine implements CloudWrites, OwnerPasswordCloud {
  SyncEngine({
    required AppDatabase db,
    required this._audit,
    required this._cloud,
    required this._secrets,
    required this._clock,
    this.appVersion = '1.0.0',
    this.batchSize = 200,
    this.pullPageSize = 500,
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
  final int pullPageSize;
  final Duration? pushEvery;
  final Duration? heartbeatEvery;
  final Duration nudgeDelay;

  /// How long sent outbox rows are kept.
  static const keepSent = Duration(days: 30);
  static const _firstRetry = Duration(seconds: 5);

  /// The clock check: warn above [clockWarnAbove] either way, clear only
  /// within [clockClearWithin]; a measurement from a slower round trip than
  /// [clockMaxRoundTrip] is ignored.
  static const clockWarnAbove = Duration(minutes: 5);
  static const clockClearWithin = Duration(minutes: 4);
  static const clockMaxRoundTrip = Duration(seconds: 10);
  static const _maxRetry = Duration(minutes: 5);

  final _changes = StreamController<SyncStatus>.broadcast();
  var _status = const SyncStatus(phase: SyncPhase.notConnected);

  /// What the push and upload last said; [_publish] adds the pull's problem
  /// and the clock.
  var _base = const SyncStatus(phase: SyncPhase.notConnected);
  String? _pullProblem;
  Duration? _clockOffset;
  var _clockWarning = false;

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
  Future<void>? _pulling;
  Future<void>? _uploading;
  var _disposed = false;

  SyncStatus get status => _status;
  Stream<SyncStatus> get changes => _changes.stream;

  void _emitPhase(
    SyncPhase phase, {
    String? problem,
    bool needsReconnect = false,
    int? uploadSent,
    int? uploadTotal,
  }) {
    _base = SyncStatus(
      phase: phase,
      lastSyncAt: _lastSyncAt,
      uploadSent: uploadSent ?? _base.uploadSent,
      uploadTotal: uploadTotal ?? _base.uploadTotal,
      problem: problem,
      needsReconnect: needsReconnect,
    );
    _publish();
  }

  /// The status shown: a pull conflict outranks online or offline (a push
  /// problem already outranks it); the clock rides along in every state.
  void _publish() {
    final base = _base;
    final pull = _pullProblem;
    final pullStops =
        pull != null &&
        (base.phase == SyncPhase.online || base.phase == SyncPhase.offline);
    _status = SyncStatus(
      phase: pullStops ? SyncPhase.problem : base.phase,
      lastSyncAt: base.lastSyncAt,
      uploadSent: base.uploadSent,
      uploadTotal: base.uploadTotal,
      problem: pullStops ? pull : base.problem,
      needsReconnect: base.needsReconnect,
      clockOffset: _clockOffset,
      clockWarning: _clockWarning,
    );
    if (!_disposed) _changes.add(_status);
  }

  // ── Starting ───────────────────────────────────────────────────────────

  Future<void> start() async {
    _deviceId = await _db.deviceId();
    _connected = await _store.get(SyncStore.deskEmail) != null;
    _uploadDone = await _store.get(SyncStore.uploadDone) == 'yes';
    _lastPushAt = DateTime.tryParse(
      await _store.get(SyncStore.lastPushAt) ?? '',
    );
    _lastSyncAt = _lastPushAt;
    final offset = int.tryParse(await _store.get(SyncStore.clockOffset) ?? '');
    _clockOffset = offset == null ? null : Duration(seconds: offset);
    _clockWarning = await _store.get(SyncStore.clockWarning) == 'on';
    if (!_connected) {
      _emitPhase(SyncPhase.notConnected);
      return;
    }
    _startTimers();
    if (!await _ensureDesk()) return;
    await prune();
    if (_uploadDone) {
      await syncNow();
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
    unawaited(_uploadDone ? _round() : continueFirstUpload());
  }

  /// Push, then pull.
  Future<void> _round() async {
    await _push();
    await _pull();
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
      await syncNow();
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

  // ── The owner's password (owner-app-3) ─────────────────────────────────

  Future<DateTime?> _time(String key) async {
    final v = await _store.get(key);
    return v == null ? null : DateTime.parse(v).toUtc();
  }

  @override
  Future<bool> isOwnerPasswordBehind() async {
    if (!_connected) return false;
    return ownerPasswordBehind(
      cloudAt: await _time(SyncStore.passwordCloudAt),
      deskAt: await _time(SyncStore.passwordDeskAt),
    );
  }

  @override
  Future<void> confirmOwnerPassword(String password) async {
    try {
      await signInOwner(password);
    } on CloudSignInRefused {
      throw const OwnerPasswordRefused();
    }
  }

  @override
  Future<void> ownerPasswordCaughtUp() async {
    final cloud = await _store.get(SyncStore.passwordCloudAt);
    if (cloud != null) await _store.set(SyncStore.passwordDeskAt, cloud);
  }

  @override
  Future<DateTime> changeOwnerPassword({
    required String current,
    required String next,
  }) async {
    await confirmOwnerPassword(current);
    try {
      // Recorded first: if setting it then fails, the desk only asks for
      // one online sign-in, which the unchanged password passes.
      final at = await _cloud.recordPasswordChange(
        id: const Uuid().v4(),
        deviceId: _deviceId,
      );
      await _cloud.updateOwnerPassword(next);
      return at;
    } on CloudOffline {
      throw const NeedsInternet();
    } on CloudSignInRefused {
      throw const OwnerCloudSignInNeeded();
    } on CloudRefused catch (e) {
      throw RefusedByCloud(
        'The new password wasn’t saved in the cloud (${e.message}). Try '
        'again.',
      );
    }
  }

  @override
  Future<void> ownerPasswordChangedHere(DateTime at) async {
    final cloud = await _time(SyncStore.passwordCloudAt);
    final iso = at.toUtc().toIso8601String();
    await _store.set(SyncStore.passwordDeskAt, iso);
    if (cloud == null || at.isAfter(cloud)) {
      await _store.set(SyncStore.passwordCloudAt, iso);
    }
  }

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
    await syncNow();
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

  /// Pushes everything queued now.
  Future<void> pushNow() {
    _retryAt = null;
    return _push();
  }

  /// Pushes, then pulls, now ("Try again now", start, after the upload).
  Future<void> syncNow() {
    _retryAt = null;
    return _round();
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
      unawaited(_uploadDone ? _round() : continueFirstUpload());
    });
  }

  /// When the next retry is due, if one is waiting.
  DateTime? get retryAt => _retryAt;

  // ── Pulling (sync-2) ───────────────────────────────────────────────────

  /// Pulls what the owner's side wrote since the cursor, now.
  Future<void> pullNow() => _pull();

  Future<void> _pull() =>
      _pulling ??= _pullLoop().whenComplete(() => _pulling = null);

  /// Page after page by `server_seq` until the cloud has no more: after
  /// days offline it simply catches up. Each page and the cursor are
  /// written in one transaction ([PulledRows]). It runs whatever the push
  /// queue is doing; a clash stops it (and only it) with a problem.
  Future<void> _pullLoop() async {
    if (!_connected || !_uploadDone || !await _ensureDesk()) return;
    final rows = PulledRows(_db, _clock);
    while (true) {
      final after = await _store.getInt(SyncStore.pullAfter);
      final sent = _clock.now();
      final PullPage page;
      try {
        page = await _cloud.pullChanges(after, limit: pullPageSize);
      } on CloudOffline {
        if (_base.phase == SyncPhase.online) _offline();
        return;
      } on CloudSignInRefused {
        await _ensureDesk();
        return;
      } on CloudRefused catch (e) {
        _pullProblem = 'The pull was refused: ${e.message}';
        _publish();
        return;
      }
      await _checkClock(page.serverTime, sent: sent, received: _clock.now());
      try {
        await rows.apply(
          page.rows,
          cursor: page.rows.isEmpty ? after : page.rows.last.seq,
        );
      } on PullConflict catch (e) {
        _pullProblem = e.message;
        _publish();
        return;
      }
      if (_pullProblem != null) {
        _pullProblem = null;
        _publish();
      }
      if (!page.more) return;
    }
  }

  // ── The clock check (sync-2) ──────────────────────────────────────────

  /// Compares this PC's clock with the server's from a pull answered
  /// between [sent] and [received]; the PC's moment is taken halfway.
  Future<void> _checkClock(
    DateTime server, {
    required DateTime sent,
    required DateTime received,
  }) async {
    final roundTrip = received.difference(sent);
    if (roundTrip > clockMaxRoundTrip) return;
    final pcAt = sent.add(roundTrip ~/ 2);
    final offset = Duration(seconds: pcAt.difference(server).inSeconds);
    _clockOffset = offset;
    await _store.set(SyncStore.clockOffset, offset.inSeconds);
    final off = offset.abs();
    if (!_clockWarning && off > clockWarnAbove) {
      _clockWarning = true;
      await _store.set(SyncStore.clockWarning, 'on');
      await _audit.recordEvent(
        action: 'sync.clock_warning',
        userId: null,
        entity: 'sync',
        entityId: _deviceId,
        details: {
          'offset_seconds': offset.inSeconds,
          'pc_time': pcAt.toUtc().toIso8601String(),
          'server_time': server.toUtc().toIso8601String(),
        },
      );
    } else if (_clockWarning && off < clockClearWithin) {
      _clockWarning = false;
      await _store.set(SyncStore.clockWarning, 'off');
    }
    _publish();
  }

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
          clockOffsetSeconds: _clockOffset?.inSeconds,
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
  Future<void> changePrices(List<PriceEdit> edits, DateTime at) async {
    await _readyForCloudWrite(owner: true);
    final PriceChangeAnswer answer;
    try {
      answer = await _cloud.changePrices(edits, at, deviceId: _deviceId);
    } on CloudOffline {
      throw const NeedsInternet();
    } on CloudSignInRefused {
      throw const OwnerCloudSignInNeeded();
    } on CloudRefused catch (e) {
      throw RefusedByCloud(e.message);
    }
    switch (answer) {
      case PricesChanged():
        return;
      case PriceMovedOn(
        :final categoryId,
        :final currentPrice,
        :final changedAt,
        :final changedOn,
      ):
        throw PriceChangedElsewhere(
          categoryId: categoryId,
          currentPrice: currentPrice,
          at: changedAt,
          changedOn: changedOn,
        );
      case PriceCategoryMissing():
        throw const SyncBlocked(
          'This desk’s latest changes haven’t reached the cloud yet.',
        );
    }
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
