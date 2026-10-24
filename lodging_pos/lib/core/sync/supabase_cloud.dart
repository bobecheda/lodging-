import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud.dart';

/// [Cloud] on Supabase: two clients on the same project, one signed in as
/// this desk, one as the owner while the owner is at the desk. Sessions are
/// kept in memory only; the desk signs in again from its secret on start.
class SupabaseCloud implements Cloud {
  SupabaseCloud({required String url, required String anonKey})
    : _desk = _client(url, anonKey),
      _owner = _client(url, anonKey);

  static SupabaseClient _client(String url, String key) => SupabaseClient(
    url,
    key,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  final SupabaseClient _desk;
  final SupabaseClient _owner;

  /// For signing the desk in again when its session can't be refreshed.
  DeskCredentials? _deskCredentials;

  static const _timeout = Duration(seconds: 30);

  /// Runs [call], turning the cloud's refusals into [CloudRefused] (with the
  /// refused row's index when the cloud names one), refused sign-ins into
  /// [CloudSignInRefused], and anything else (no network, a timeout, the
  /// HTTP client's errors) into [CloudOffline].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on PostgrestException catch (e) {
      throw CloudRefused(e.message, index: int.tryParse('${e.details}'));
    } on FunctionException catch (e) {
      final details = e.details;
      throw CloudRefused(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'The cloud refused the request (${e.status}).',
      );
    } on AuthRetryableFetchException catch (e) {
      throw CloudOffline(e.message);
    } on AuthException catch (e) {
      throw CloudSignInRefused(e.message);
    } on SocketException catch (e) {
      throw CloudOffline(e.message);
    } on TimeoutException {
      throw const CloudOffline('timed out');
    } on HandshakeException catch (e) {
      throw CloudOffline(e.message);
    } on Exception catch (e) {
      // The HTTP client's own errors (it wraps socket failures): the cloud
      // can't be reached.
      throw CloudOffline('$e');
    }
  }

  /// A desk call; signs the desk in again once if its session lapsed.
  Future<T> _asDesk<T>(Future<T> Function(SupabaseClient c) call) async {
    if (_desk.auth.currentSession == null) {
      final credentials = _deskCredentials;
      if (credentials == null) {
        throw const CloudSignInRefused('This desk is not signed in.');
      }
      await signInDesk(credentials);
    }
    return _guard(() => call(_desk));
  }

  Future<T> _asOwner<T>(Future<T> Function(SupabaseClient c) call) {
    if (_owner.auth.currentSession == null) {
      throw const CloudSignInRefused('The owner is not signed in.');
    }
    return _guard(() => call(_owner));
  }

  static String _time(DateTime t) => t.toUtc().toIso8601String();

  static CloudDecision _decision(Object? answer) {
    final map = (answer as Map).cast<String, Object?>();
    return switch (map['status']) {
      'decided' || 'withdrawn' => const Decided(),
      'already_decided' => AlreadyDecided(
        decision: map['decision']! as String,
        decidedByName: map['decided_by_name'] as String?,
        decidedAt: DateTime.parse(map['decided_at']! as String),
      ),
      'already_withdrawn' => const AlreadyWithdrawn(),
      'stale' => StaleInCloud(map['current_price']! as int),
      'missing' => const MissingInCloud(),
      final other => throw CloudRefused('Unexpected answer: $other'),
    };
  }

  @override
  Future<DeskCredentials> connectDesk(ConnectRequest r) => _guard(() async {
    final response = await _desk.functions.invoke(
      'connect-desk',
      body: {
        'mode': r.reconnect ? 'reconnect' : 'connect',
        'install_code': ?r.installCode,
        'owner_email': r.ownerEmail,
        'owner_password': r.ownerPassword,
        'owner_user_id': r.ownerUserId,
        'device_id': r.deviceId,
      },
    );
    final data = (response.data as Map).cast<String, Object?>();
    return DeskCredentials(
      email: data['device_email']! as String,
      secret: data['device_secret']! as String,
    );
  });

  @override
  Future<void> signInDesk(DeskCredentials credentials) => _guard(() async {
    await _desk.auth.signInWithPassword(
      email: credentials.email,
      password: credentials.secret,
    );
    _deskCredentials = credentials;
  });

  @override
  bool get deskSignedIn => _desk.auth.currentSession != null;

  @override
  Future<bool> firstUploadDone() =>
      _asDesk((c) async => await c.rpc('first_upload_done') == true);

  @override
  Future<int> importDeskRows(List<CloudRow> rows) => _asDesk(
    (c) async => await c.rpc(
      'import_desk_rows',
      params: {
        'p_rows': [for (final r in rows) r.toJson()],
      },
    ) as int,
  );

  @override
  Future<int> pushChanges(List<CloudRow> rows) => _asDesk(
    (c) async => await c.rpc(
      'push_changes',
      params: {
        'p_rows': [for (final r in rows) r.toJson()],
      },
    ) as int,
  );

  @override
  Future<CloudDecision> withdrawPriceRequest({
    required String requestId,
    required String by,
    required String? reason,
    required DateTime at,
  }) => _asDesk(
    (c) async => _decision(
      await c.rpc(
        'withdraw_price_request',
        params: {
          'p_request_id': requestId,
          'p_by': by,
          'p_reason': reason,
          'p_at': _time(at),
        },
      ),
    ),
  );

  @override
  Future<void> heartbeat(DeskHeartbeat h) => _asDesk(
    (c) => c.rpc(
      'desk_heartbeat',
      params: {
        'p_pending': h.pending,
        'p_last_push_at': h.lastPushAt == null ? null : _time(h.lastPushAt!),
        'p_problem': h.problem,
        'p_app_version': h.appVersion,
        'p_clock_offset': h.clockOffsetSeconds,
      },
    ),
  );

  @override
  Future<PullPage> pullChanges(int after, {required int limit}) =>
      _asDesk((c) async {
        final answer = (await c.rpc(
          'pull_changes',
          params: {'p_after': after, 'p_limit': limit},
        ) as Map).cast<String, Object?>();
        return PullPage(
          serverTime: DateTime.parse(answer['server_time']! as String),
          more: answer['more'] == true,
          rows: [
            for (final r in (answer['rows']! as List).cast<Map>())
              PulledRow(
                r['table']! as String,
                (r['seq']! as num).toInt(),
                (r['row']! as Map).cast<String, Object?>(),
              ),
          ],
        );
      });

  @override
  Future<void> signInOwner(String email, String password) => _guard(
    () => _owner.auth.signInWithPassword(email: email, password: password),
  );

  @override
  bool get ownerSignedIn => _owner.auth.currentSession != null;

  @override
  Future<void> signOutOwner() async {
    try {
      await _owner.auth.signOut(scope: SignOutScope.local);
    } on Exception {
      // Offline: the session is dropped locally all the same.
    }
  }

  @override
  Future<int> importOwnerRows(String deviceId, List<CloudRow> rows) => _asOwner(
    (c) async => await c.rpc(
      'import_owner_rows',
      params: {
        'p_device_id': deviceId,
        'p_rows': [for (final r in rows) r.toJson()],
      },
    ) as int,
  );

  @override
  Future<void> finishFirstUpload(String deviceId) => _asOwner(
    (c) => c.rpc('finish_first_upload', params: {'p_device_id': deviceId}),
  );

  @override
  Future<void> setPrices(Map<String, int> prices, DateTime at) => _asOwner(
    (c) => c.rpc('set_prices', params: {'p_prices': prices, 'p_at': _time(at)}),
  );

  @override
  Future<PriceChangeAnswer> changePrices(
    List<PriceEdit> edits,
    DateTime at, {
    required String deviceId,
  }) => _asOwner((c) async {
    final map = ((await c.rpc(
      'change_prices',
      params: {
        'p_changes': [for (final e in edits) e.toJson()],
        'p_at': _time(at),
        'p_device_id': deviceId,
      },
    )) as Map).cast<String, Object?>();
    return switch (map['status']) {
      'changed' => const PricesChanged(),
      'stale' => PriceMovedOn(
        categoryId: map['category_id']! as String,
        currentPrice: map['current_price']! as int,
        changedAt: DateTime.parse(map['changed_at']! as String).toUtc(),
        changedOn: map['changed_on'] as String?,
      ),
      'missing' => const PriceCategoryMissing(),
      final other => throw CloudRefused('Unexpected answer: $other'),
    };
  });

  @override
  Future<CloudDecision> decideRefund({
    required String id,
    required String refundId,
    required String decision,
    required String? note,
    required DateTime at,
    required String deviceId,
  }) => _asOwner(
    (c) async => _decision(
      await c.rpc(
        'decide_refund',
        params: {
          'p_id': id,
          'p_refund_id': refundId,
          'p_decision': decision,
          'p_note': note,
          'p_at': _time(at),
          'p_device_id': deviceId,
        },
      ),
    ),
  );

  @override
  Future<CloudDecision> decidePriceRequest({
    required String id,
    required String requestId,
    required String decision,
    required String? note,
    required DateTime at,
    required String deviceId,
  }) => _asOwner(
    (c) async => _decision(
      await c.rpc(
        'decide_price_request',
        params: {
          'p_id': id,
          'p_request_id': requestId,
          'p_decision': decision,
          'p_note': note,
          'p_at': _time(at),
          'p_device_id': deviceId,
        },
      ),
    ),
  );

  @override
  Future<void> close() async {
    await _desk.dispose();
    await _owner.dispose();
  }
}
