import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'owner_cloud.dart';

/// [OwnerCloud] on Supabase. The sign-in session (and this install's id)
/// is kept in the phone's secure storage so the owner stays signed in until
/// Sign out; nothing else is ever stored on the phone.
class SupabaseOwnerCloud implements OwnerCloud {
  SupabaseOwnerCloud({
    required String url,
    required String anonKey,
    FlutterSecureStorage? storage,
  }) : _client = SupabaseClient(
         url,
         anonKey,
         authOptions: const AuthClientOptions(
           authFlowType: AuthFlowType.implicit,
         ),
       ),
       _storage = storage ?? const FlutterSecureStorage() {
    _changes = _client.auth.onAuthStateChange.listen((state) {
      final session = state.session;
      switch (state.event) {
        case AuthChangeEvent.signedIn ||
                AuthChangeEvent.tokenRefreshed ||
                AuthChangeEvent.userUpdated
            when session != null:
          unawaited(
            _storage.write(key: _sessionKey, value: jsonEncode(session)),
          );
        case AuthChangeEvent.signedOut:
          unawaited(_storage.delete(key: _sessionKey));
        default:
      }
    });
  }

  final SupabaseClient _client;
  final FlutterSecureStorage _storage;
  // Lives as long as the app.
  // ignore: unused_field
  late final StreamSubscription<AuthState> _changes;

  static const _sessionKey = 'lodging_pos.owner_session';
  static const _deviceKey = 'lodging_pos.owner_device_id';
  static const _timeout = Duration(seconds: 30);
  static const _page = 1000;

  /// An `in` filter's values per request, so the URL stays short.
  static const _inChunk = 100;

  @override
  Future<OwnerSignIn?> restore() async {
    final stored = await _storage.read(key: _sessionKey);
    if (stored == null) return null;
    try {
      await _client.auth.setInitialSession(stored);
    } on AuthException {
      await _storage.delete(key: _sessionKey);
      return null;
    }
    return _owner(_client.auth.currentSession);
  }

  @override
  Future<OwnerSignIn> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _guard(
      () => _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      ),
      signingIn: true,
    );
    final owner = _owner(response.session);
    if (owner == null) {
      await _client.auth.signOut();
      throw const OwnerSignInRefused('This account isn’t the owner’s.');
    }
    return owner;
  }

  OwnerSignIn? _owner(Session? session) {
    final user = session?.user;
    final meta = user?.appMetadata ?? const {};
    final userId = meta['user_id'];
    if (meta['role'] != 'owner' || userId is! String) return null;
    return OwnerSignIn(userId: userId, email: user?.email ?? '');
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on Exception {
      // Offline: the session is forgotten here all the same.
    }
    await _storage.delete(key: _sessionKey);
  }

  @override
  Future<List<Map<String, Object?>>> rows(
    String table,
    List<String> columns, {
    List<Where> where = const [],
    String? orderBy,
    bool newestFirst = false,
    int? limit,
  }) async {
    if (columns.isEmpty || columns.contains('*')) {
      throw ArgumentError('Name the columns to read from $table.');
    }
    final big = where.whereType<InList>().where(
      (f) => f.values.length > _inChunk,
    );
    if (big.isNotEmpty) {
      final f = big.first;
      final rest = [
        for (final w in where)
          if (!identical(w, f)) w,
      ];
      return [
        for (var i = 0; i < f.values.length; i += _inChunk)
          ...await rows(
            table,
            columns,
            where: [
              ...rest,
              InList(
                f.column,
                f.values.sublist(
                  i,
                  i + _inChunk > f.values.length
                      ? f.values.length
                      : i + _inChunk,
                ),
              ),
            ],
            orderBy: orderBy,
            newestFirst: newestFirst,
          ),
      ];
    }
    final all = <Map<String, Object?>>[];
    for (var from = 0; ; from += _page) {
      final page = await _call(() {
        var q = _client.from(table).select(columns.join(','));
        for (final w in where) {
          q = switch (w) {
            Eq(:final column, :final value) => q.eq(column, value),
            Gte(:final column, :final value) => q.gte(column, value),
            IsNull(:final column) => q.isFilter(column, null),
            InList(:final column, :final values) => q.inFilter(column, values),
          };
        }
        final size = limit == null || limit > _page ? _page : limit;
        return (orderBy == null ? q : q.order(orderBy, ascending: !newestFirst))
            .range(from, from + size - 1);
      });
      all.addAll(page);
      if (limit != null && all.length >= limit) return all.take(limit).toList();
      if (page.length < _page) return all;
    }
  }

  @override
  Future<void> verifyPassword(String password) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw const OwnerSignInRefused('Sign in again.');
    try {
      await _guard(
        () => _client.auth.signInWithPassword(email: email, password: password),
        signingIn: true,
      );
    } on OwnerSignInRefused {
      throw const OwnerSignInRefused('That isn’t your current password.');
    }
  }

  @override
  Future<void> updatePassword(String password) =>
      _call(() => _client.auth.updateUser(UserAttributes(password: password)));

  @override
  Future<void> signOutOtherSessions() =>
      _call(() => _client.auth.signOut(scope: SignOutScope.others));

  @override
  Future<Object?> rpc(String name, Map<String, Object?> params) =>
      _call(() => _client.rpc(name, params: params));

  @override
  Future<String> deviceId() async {
    final kept = await _storage.read(key: _deviceKey);
    if (kept != null) return kept;
    final made = const Uuid().v4();
    await _storage.write(key: _deviceKey, value: made);
    return made;
  }

  /// A call as the owner, the session renewed first when it has expired.
  Future<T> _call<T>(Future<T> Function() call) => _guard(() async {
    if (await _client.auth.getSession() == null) {
      throw const OwnerSignInRefused('Sign in again.');
    }
    return call();
  });

  /// Turns the cloud's refusals into [OwnerCloudRefused], a session that
  /// can't be renewed (or a refused sign-in) into [OwnerSignInRefused], and
  /// anything else (no network, a timeout) into [OwnerCloudOffline]. Raw
  /// error text is never shown, except the database's own messages.
  Future<T> _guard<T>(
    Future<T> Function() call, {
    bool signingIn = false,
  }) async {
    try {
      return await call().timeout(_timeout);
    } on OwnerSignInRefused {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST301' || e.code == '401') {
        throw const OwnerSignInRefused('Sign in again.');
      }
      throw OwnerCloudRefused(e.message);
    } on AuthRetryableFetchException catch (e) {
      throw OwnerCloudOffline(e.message);
    } on AuthException {
      if (!signingIn) await _storage.delete(key: _sessionKey);
      throw OwnerSignInRefused(
        signingIn ? 'Wrong email or password.' : 'Sign in again.',
      );
    } on TimeoutException {
      throw const OwnerCloudOffline('timed out');
    } on Exception catch (e) {
      // The HTTP client's own errors (it wraps socket failures).
      throw OwnerCloudOffline('$e');
    }
  }
}
