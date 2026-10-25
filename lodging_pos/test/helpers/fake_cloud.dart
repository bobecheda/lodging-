import 'package:lodging_pos/core/sync/cloud.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';

/// The owner's cloud email in tests (made up; the password is
/// `testOwner.password` from fixtures.dart).
const testOwnerEmail = 'owner@lodging.test';

/// The cloud in memory, with the rules of supabase/migrations that the
/// desk relies on: rows upserted only when newer, audit rows and decisions
/// insert-if-absent, a category's price never taken from a desk update,
/// the desk pushing only after its first upload and never the owner's
/// tables, the first decision winning; payments, charges and voids
/// insert-only (a payment's print_count only rises); the pull by
/// server_seq. Switches simulate trouble.
class FakeCloud implements Cloud {
  FakeCloud({this.serverNow});

  /// The server's clock, for the pull's `server_time` (set it to the
  /// test's clock, skewed to test the clock check).
  DateTime Function()? serverNow;

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

  /// The server_seq of each row's last write ("table/key").
  final _seqs = <String, int>{};
  var _seq = 0;

  /// Calls to [pullChanges], with the cursor each asked from.
  final pulls = <int>[];

  void _stamp(String table, String key) => _seqs['$table/$key'] = ++_seq;

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
      _stamp(r.table, key);
      return;
    }
    if (r.table == 'audit_log' ||
        r.table == 'stay_charges' ||
        r.table == 'voids' ||
        SyncStore.ownerTables.contains(r.table)) {
      return;
    }
    if (r.table == 'payments') {
      final count = r.row['print_count']! as int;
      if (count > (existing['print_count']! as int)) {
        existing['print_count'] = count;
        _stamp(r.table, key);
      }
      return;
    }
    final incoming = DateTime.parse(r.row['updated_at']! as String);
    final stored = DateTime.parse(existing['updated_at']! as String);
    if (!incoming.isAfter(stored)) return;
    rows[key] = {
      ...r.row,
      'created_at': existing['created_at'],
      if (r.table == 'bed_categories') ...{
        'price_per_night': existing['price_per_night'],
        'price_updated_at': existing['price_updated_at'],
      },
    };
    _stamp(r.table, key);
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
    _stamp('price_requests', requestId);
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

  /// The next password update fails (after the change was recorded).
  var failPasswordUpdate = false;

  @override
  Future<DateTime> recordPasswordChange({
    required String id,
    required String deviceId,
  }) async {
    _asOwner();
    final rows = tables.putIfAbsent('owner_password_changes', () => {});
    final existing = rows[id];
    if (existing != null) {
      return DateTime.parse(existing['changed_at']! as String);
    }
    final now = serverNow!().toUtc();
    rows[id] = {
      'id': id,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'device_id': deviceId,
      'user_id': ownerUserId,
      'changed_at': now.toIso8601String(),
    };
    _stamp('owner_password_changes', id);
    return now;
  }

  @override
  Future<void> updateOwnerPassword(String password) async {
    _asOwner();
    if (failPasswordUpdate) {
      failPasswordUpdate = false;
      throw const CloudRefused('the password could not be updated');
    }
    ownerPassword = password;
  }

  /// The owner changes their password on the phone: recorded, set, and
  /// their other sessions (the desk's owner sign-in) ended. The desk's own
  /// sign-in is untouched.
  void phoneChangesPassword(String password) {
    final now = serverNow!().toUtc().toIso8601String();
    final id = 'pc-${count('owner_password_changes') + 1}';
    tables.putIfAbsent('owner_password_changes', () => {})[id] = {
      'id': id,
      'created_at': now,
      'updated_at': now,
      'device_id': 'phone-1',
      'user_id': ownerUserId,
      'changed_at': now,
    };
    _stamp('owner_password_changes', id);
    ownerPassword = password;
    _ownerSignedIn = false;
  }

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
      _price(key, value, at);
    }
  }

  /// Where each category's price was last edited: (device id, time).
  final priceEdits = <String, (String, DateTime)>{};

  @override
  Future<PriceChangeAnswer> changePrices(
    List<PriceEdit> edits,
    DateTime at, {
    required String deviceId,
  }) async {
    _asOwner();
    for (final e in edits) {
      final category = row('bed_categories', e.categoryId);
      if (category == null) return const PriceCategoryMissing();
      final current = category['price_per_night']! as int;
      if (current != e.expected) {
        final (device, editedAt) =
            priceEdits[e.categoryId] ??
            ('', DateTime.parse(category['price_updated_at']! as String));
        return PriceMovedOn(
          categoryId: e.categoryId,
          currentPrice: current,
          changedAt: editedAt,
          changedOn: device.isEmpty
              ? null
              : devices.containsKey(device)
              ? 'desk'
              : 'phone',
        );
      }
    }
    for (final e in edits) {
      _price(e.categoryId, e.price, at);
      priceEdits[e.categoryId] = (deviceId, at);
    }
    return const PricesChanged();
  }

  /// The owner's path sets a price: pulled afterwards.
  void _price(String categoryId, int price, DateTime at) {
    row('bed_categories', categoryId)!
      ..['price_per_night'] = price
      ..['price_updated_at'] = at.toIso8601String();
    _stamp('bed_categories', categoryId);
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
    _stamp('refund_decisions', id);
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
    _stamp('price_decisions', id);
    if (decision == 'approved') {
      _price(category['id']! as String, request['new_price']! as int, at);
    }
    return const Decided();
  }

  /// Another device (the phone) decides first; approving a price request
  /// sets its price too.
  void decideElsewhere(
    String table,
    String column,
    String target, {
    required String decision,
    required DateTime at,
    String? note,
  }) {
    final id = 'elsewhere-$target';
    tables.putIfAbsent(table, () => {})[id] = _decision(
      id,
      column,
      target,
      decision,
      note ?? (decision == 'rejected' ? 'Decided on the phone' : null),
      at,
      'phone',
    );
    _stamp(table, id);
    if (table == 'price_decisions' && decision == 'approved') {
      final request = row('price_requests', target)!;
      _price(
        request['category_id']! as String,
        request['new_price']! as int,
        at,
      );
    }
  }

  /// The owner changes a price on the phone.
  /// The owner changes a price on the phone.
  void setPriceElsewhere(String categoryId, int price, DateTime at) {
    _price(categoryId, price, at);
    priceEdits[categoryId] = ('phone-1', at);
  }

  /// An audit row written on the phone (the owner's action).
  void phoneAudit(String id, {required String action, required DateTime at}) {
    tables.putIfAbsent('audit_log', () => {})[id] = {
      'id': id,
      'created_at': at.toIso8601String(),
      'updated_at': at.toIso8601String(),
      'device_id': 'phone',
      'at': at.toIso8601String(),
      'operation_id': 'op-$id',
      'user_id': ownerUserId,
      'action': action,
      'entity': 'refund_decisions',
      'entity_id': id,
      'before_json': null,
      'after_json': '{}',
    };
    _stamp('audit_log', id);
  }

  @override
  Future<PullPage> pullChanges(int after, {required int limit}) async {
    _asDesk();
    pulls.add(after);
    final now = serverNow;
    if (now == null) throw StateError('Set FakeCloud.serverNow.');
    final rows = <PulledRow>[];
    for (final MapEntry(key: tag, value: seq) in _seqs.entries) {
      if (seq <= after) continue;
      final [table, key] = tag.split('/');
      final r = row(table, key)!;
      switch (table) {
        case 'refund_decisions' ||
            'price_decisions' ||
            'owner_password_changes':
          rows.add(PulledRow(table, seq, {...r}));
        case 'bed_categories' when r['price_updated_at'] != null:
          rows.add(
            PulledRow(table, seq, {
              'id': r['id'],
              'price_per_night': r['price_per_night'],
              'price_updated_at': r['price_updated_at'],
            }),
          );
        case 'audit_log' when r['device_id'] != _deskDevice:
          rows.add(PulledRow(table, seq, {...r}));
      }
    }
    rows.sort((a, b) => a.seq.compareTo(b.seq));
    return PullPage(
      serverTime: now(),
      rows: rows.take(limit).toList(),
      more: rows.length > limit,
    );
  }

  @override
  Future<void> close() async {}
}
