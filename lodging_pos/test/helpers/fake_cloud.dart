import 'package:lodging_pos/core/sync/cloud.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';

/// The owner's cloud email in tests (made up; the password is
/// `testOwner.password` from fixtures.dart).
const testOwnerEmail = 'owner@lodging.test';

/// The cloud in memory, with the rules of supabase/migrations that the
/// desk relies on: rows upserted only when newer, audit rows and decisions
/// insert-if-absent, a category's price never taken from a desk update,
/// the desk pushing only after its first upload and never the owner's
/// tables, the first decision winning. Switches simulate trouble.
class FakeCloud implements Cloud {
  /// table → key → row.
  final tables = <String, Map<String, Map<String, Object?>>>{};

  /// Valid one-time install codes.
  final installCodes = <String>{'ABCD-EFGH-JKLM'};
  final heartbeats = <DeskHeartbeat>[];
  final pushes = <List<CloudRow>>[];

  /// The owner account: email → password, and its desk user id.
  String? ownerEmail;
  String? ownerPassword;
  String? ownerUserId;

  /// device id → first upload finished.
  final devices = <String, bool>{};
  DeskCredentials? _deskKey;
  String? _deskDevice;

  // ── Switches ───────────────────────────────────────────────────────────

  /// Every call fails as if there were no internet.
  var offline = false;

  /// The next push (or import) is stored, then fails as if the answer was
  /// lost on the way back.
  var loseNextAnswer = false;

  /// After this many more desk calls, the network drops ([offline]).
  int? goOfflineAfter;

  /// Rows received by imports, counting repeats.
  var importedRows = 0;
  var _keys = 0;

  /// Refuses a row: (table, row) → a message, or null to accept.
  String? Function(String table, Map<String, Object?> row)? refuse;

  var _deskSignedIn = false;
  var _ownerSignedIn = false;

  int count(String table) => tables[table]?.length ?? 0;
  Map<String, Object?>? row(String table, String key) => tables[table]?[key];

  void _online() {
    if (offline) throw const CloudOffline('no network');
  }

  void _asDesk() {
    if (goOfflineAfter case final n?) {
      if (n == 0) offline = true;
      goOfflineAfter = n - 1;
    }
    _online();
    if (!_deskSignedIn) throw const CloudSignInRefused('not signed in');
  }

  void _asOwner() {
    _online();
    if (!_ownerSignedIn) throw const CloudSignInRefused('owner not signed in');
  }

  static String _key(String table) => table == 'settings' ? 'key' : 'id';

  void _upsert(CloudRow r) {
    final rows = tables.putIfAbsent(r.table, () => {});
    final key = r.row[_key(r.table)]! as String;
    final existing = rows[key];
    if (existing == null) {
      rows[key] = {...r.row};
      return;
    }
    if (r.table == 'audit_log' || SyncStore.ownerTables.contains(r.table)) {
      return;
    }
    final incoming = DateTime.parse(r.row['updated_at']! as String);
    final stored = DateTime.parse(existing['updated_at']! as String);
    if (!incoming.isAfter(stored)) return;
    rows[key] = {
      ...r.row,
      'created_at': existing['created_at'],
      if (r.table == 'bed_categories')
        'price_per_night': existing['price_per_night'],
    };
  }

  int _apply(List<CloudRow> rows, Set<String> allowed) {
    for (final (i, r) in rows.indexed) {
      if (!allowed.contains(r.table)) {
        throw CloudRefused('this sign-in can’t write ${r.table}', index: i);
      }
      final message = refuse?.call(r.table, r.row);
      if (message != null) {
        throw CloudRefused(
          '${r.table} ${r.row[_key(r.table)]}: $message',
          index: i,
        );
      }
    }
    for (final r in rows) {
      _upsert(r);
    }
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw const CloudOffline('answer lost');
    }
    return rows.length;
  }

  @override
  Future<DeskCredentials> connectDesk(ConnectRequest r) async {
    _online();
    if (ownerEmail != null) {
      if (ownerEmail != r.ownerEmail || ownerPassword != r.ownerPassword) {
        throw const CloudRefused(
          'Wrong email or password for the owner’s cloud account.',
        );
      }
    } else if (r.reconnect) {
      throw const CloudRefused('This desk has never been connected.');
    }
    if (!r.reconnect && !installCodes.remove(r.installCode)) {
      throw const CloudRefused(
        'That install code isn’t valid, has expired or has been used.',
      );
    }
    if (r.reconnect && !devices.containsKey(r.deviceId)) {
      throw const CloudRefused('This desk has never been connected.');
    }
    ownerEmail ??= r.ownerEmail;
    ownerPassword ??= r.ownerPassword;
    ownerUserId ??= r.ownerUserId;
    devices.putIfAbsent(r.deviceId, () => false);
    _deskDevice = r.deviceId;
    return _deskKey = DeskCredentials(
      email: '${r.deviceId}@desk.lodging.invalid',
      secret: 'secret-${++_keys}',
    );
  }

  @override
  Future<void> signInDesk(DeskCredentials credentials) async {
    _online();
    if (credentials.secret != _deskKey?.secret) {
      throw const CloudSignInRefused('Invalid login credentials');
    }
    _deskSignedIn = true;
  }

  @override
  bool get deskSignedIn => _deskSignedIn;

  /// The desk's session lapsed (it signs in again from its key).
  void dropDeskSession() => _deskSignedIn = false;

  @override
  Future<bool> firstUploadDone() async {
    _asDesk();
    return devices[_deskDevice] ?? false;
  }

  static final _deskTables = {...SyncStore.deskTables};

  @override
  Future<int> importDeskRows(List<CloudRow> rows) async {
    _asDesk();
    if (devices[_deskDevice] == true) {
      throw const CloudRefused('the first upload is already finished');
    }
    importedRows += rows.length;
    return _apply(rows, _deskTables);
  }

  @override
  Future<int> pushChanges(List<CloudRow> rows) async {
    _asDesk();
    if (devices[_deskDevice] != true) {
      throw const CloudRefused('the first upload is not finished');
    }
    if (rows.any((r) => r.row['device_id'] != _deskDevice)) {
      throw const CloudRefused('a desk pushes only its own rows');
    }
    pushes.add(rows);
    return _apply(rows, _deskTables);
  }

  @override
  Future<CloudDecision> withdrawPriceRequest({
    required String requestId,
    required String by,
    required String? reason,
    required DateTime at,
  }) async {
    _asDesk();
    final request = row('price_requests', requestId);
    if (request == null) return const MissingInCloud();
    final decision = _decisionFor('price_decisions', 'request_id', requestId);
    if (decision != null) return _already(decision);
    if (request['withdrawn_at'] != null) return const AlreadyWithdrawn();
    request
      ..['withdrawn_at'] = at.toIso8601String()
      ..['withdrawn_by'] = by
      ..['withdraw_reason'] = reason
      ..['updated_at'] = at.toIso8601String();
    return const Decided();
  }

  @override
  Future<void> heartbeat(DeskHeartbeat heartbeat) async {
    _asDesk();
    heartbeats.add(heartbeat);
  }

  @override
  Future<void> signInOwner(String email, String password) async {
    _online();
    if (email != ownerEmail || password != ownerPassword) {
      throw const CloudSignInRefused('Invalid login credentials');
    }
    _ownerSignedIn = true;
  }

  @override
  bool get ownerSignedIn => _ownerSignedIn;

  @override
  Future<void> signOutOwner() async => _ownerSignedIn = false;

  @override
  Future<int> importOwnerRows(String deviceId, List<CloudRow> rows) async {
    _asOwner();
    if (devices[deviceId] != false) {
      throw const CloudRefused('no first upload is waiting for this desk');
    }
    importedRows += rows.length;
    return _apply(rows, {...SyncStore.ownerTables});
  }

  @override
  Future<void> finishFirstUpload(String deviceId) async {
    _asOwner();
    devices[deviceId] = true;
  }

  @override
  Future<void> setPrices(Map<String, int> prices, DateTime at) async {
    _asOwner();
    for (final MapEntry(:key, :value) in prices.entries) {
      final category = row('bed_categories', key);
      if (category == null) throw CloudRefused('category $key is missing');
      category['price_per_night'] = value;
    }
  }

  Map<String, Object?>? _decisionFor(String table, String column, String id) {
    for (final d in tables[table]?.values ?? const <Map<String, Object?>>[]) {
      if (d[column] == id) return d;
    }
    return null;
  }

  CloudDecision _already(Map<String, Object?> d) => AlreadyDecided(
    decision: d['decision']! as String,
    decidedByName:
        row('users', d['decided_by']! as String)?['full_name'] as String?,
    decidedAt: DateTime.parse(d['decided_at']! as String),
  );

  Map<String, Object?> _decision(
    String id,
    String column,
    String target,
    String decision,
    String? note,
    DateTime at,
    String deviceId,
  ) => {
    'id': id,
    'created_at': at.toIso8601String(),
    'updated_at': at.toIso8601String(),
    'device_id': deviceId,
    column: target,
    'decision': decision,
    'note': note,
    'decided_by': ownerUserId,
    'decided_at': at.toIso8601String(),
  };

  @override
  Future<CloudDecision> decideRefund({
    required String id,
    required String refundId,
    required String decision,
    required String? note,
    required DateTime at,
    required String deviceId,
  }) async {
    _asOwner();
    final existing = _decisionFor('refund_decisions', 'refund_id', refundId);
    if (existing != null) {
      return existing['id'] == id ? const Decided() : _already(existing);
    }
    if (row('refunds', refundId) == null) return const MissingInCloud();
    tables.putIfAbsent('refund_decisions', () => {})[id] = _decision(
      id,
      'refund_id',
      refundId,
      decision,
      note,
      at,
      deviceId,
    );
    return const Decided();
  }

  @override
  Future<CloudDecision> decidePriceRequest({
    required String id,
    required String requestId,
    required String decision,
    required String? note,
    required DateTime at,
    required String deviceId,
  }) async {
    _asOwner();
    final existing = _decisionFor('price_decisions', 'request_id', requestId);
    if (existing != null) {
      return existing['id'] == id ? const Decided() : _already(existing);
    }
    final request = row('price_requests', requestId);
    if (request == null) return const MissingInCloud();
    if (request['withdrawn_at'] != null) return const AlreadyWithdrawn();
    final category = row('bed_categories', request['category_id']! as String)!;
    if (decision == 'approved' &&
        category['price_per_night'] != request['old_price']) {
      return StaleInCloud(category['price_per_night']! as int);
    }
    tables.putIfAbsent('price_decisions', () => {})[id] = _decision(
      id,
      'request_id',
      requestId,
      decision,
      note,
      at,
      deviceId,
    );
    if (decision == 'approved') {
      category['price_per_night'] = request['new_price'];
    }
    return const Decided();
  }

  /// Another device (the phone) decides first.
  void decideElsewhere(
    String table,
    String column,
    String target, {
    required String decision,
    required DateTime at,
  }) {
    tables.putIfAbsent(table, () => {})['elsewhere-$target'] = _decision(
      'elsewhere-$target',
      column,
      target,
      decision,
      decision == 'rejected' ? 'Decided on the phone' : null,
      at,
      'phone',
    );
  }

  @override
  Future<void> close() async {}
}
