import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock.dart';
import '../data/owner_cloud.dart';
import '../data/owner_refunds_repository.dart';
import '../data/owner_today_repository.dart';
import '../data/supabase_owner_cloud.dart';
import '../domain/owner_today.dart';

part 'owner_providers.g.dart';

/// The Supabase project, from `secrets.json` at build time; null in a build
/// without it (the sign-in screen says so).
@Riverpod(keepAlive: true)
OwnerCloud? ownerCloud(Ref ref) {
  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || anonKey.isEmpty) return null;
  return SupabaseOwnerCloud(url: url, anonKey: anonKey);
}

/// How often Today reloads while open; null turns the timer off (tests).
@Riverpod(keepAlive: true)
Duration? ownerRefreshInterval(Ref ref) => const Duration(seconds: 60);

/// The owner's sign-in on this phone: kept until Sign out (or until the
/// cloud stops renewing it, e.g. after a password change elsewhere).
@Riverpod(keepAlive: true)
class OwnerSession extends _$OwnerSession {
  @override
  Future<OwnerSignIn?> build() async =>
      await ref.watch(ownerCloudProvider)?.restore();

  /// Throws [OwnerSignInRefused] or [OwnerCloudOffline].
  Future<void> signIn({required String email, required String password}) async {
    final cloud = ref.read(ownerCloudProvider);
    if (cloud == null) return;
    final owner = await cloud.signIn(email: email, password: password);
    state = AsyncData(owner);
  }

  Future<void> signOut() async {
    await ref.read(ownerCloudProvider)?.signOut();
    state = const AsyncData(null);
  }

  /// The cloud refused the session: back to sign-in.
  void ended() => state = const AsyncData(null);
}

/// The signed-in owner as the domain rules see them. The cloud checked the
/// role at sign-in (`app_metadata.role`).
UserAccount ownerAccount(OwnerSignIn owner) => UserAccount(
  id: owner.userId,
  fullName: '',
  username: '',
  role: Role.owner,
  isActive: true,
  mustChangePassword: false,
);

/// Today as last loaded, kept in memory only: shown on as it was (marked
/// offline) while the phone can't reach the cloud.
final class OwnerSnapshot {
  const OwnerSnapshot(
    this.today, {
    required this.loadedAt,
    this.offline = false,
  });
  final OwnerToday today;

  /// UTC.
  final DateTime loadedAt;

  /// The last reload failed for want of a connection.
  final bool offline;
}

/// Today: loaded on open, again on return to the app (the shell), on a
/// pull and every [ownerRefreshInterval]. Null once signed out: the
/// figures are dropped.
@Riverpod(keepAlive: true)
class OwnerTodayData extends _$OwnerTodayData {
  @override
  Future<OwnerSnapshot?> build() async {
    final signedIn = ref.watch(ownerSessionProvider).value;
    if (signedIn == null) return null;
    final every = ref.watch(ownerRefreshIntervalProvider);
    if (every != null) {
      final timer = Timer.periodic(every, (_) => unawaited(refresh()));
      ref.onDispose(timer.cancel);
    }
    return _load();
  }

  Future<OwnerSnapshot> _load() async {
    final cloud = ref.read(ownerCloudProvider)!;
    final now = ref.read(clockProvider).now();
    try {
      return OwnerSnapshot(
        await OwnerTodayRepository(cloud).load(now),
        loadedAt: now,
      );
    } on OwnerSignInRefused {
      ref.read(ownerSessionProvider.notifier).ended();
      rethrow;
    }
  }

  /// Loads again; offline, the last figures stay, marked offline. Any
  /// other failure keeps them too, unless there are none yet.
  Future<void> refresh() async {
    if (ref.read(ownerSessionProvider).value == null) return;
    try {
      final next = await _load();
      if (ref.mounted) state = AsyncData(next);
    } on OwnerCloudOffline catch (e, stack) {
      if (!ref.mounted) return;
      final last = state.value;
      state = last == null
          ? AsyncError(e, stack)
          : AsyncData(
              OwnerSnapshot(last.today, loadedAt: last.loadedAt, offline: true),
            );
    } on Exception catch (e, stack) {
      if (ref.mounted && state.value == null) state = AsyncError(e, stack);
    }
  }
}

@Riverpod(keepAlive: true)
OwnerRefundsRepository ownerRefundsRepository(Ref ref) =>
    OwnerRefundsRepository(ref.watch(ownerCloudProvider)!);

/// One refund's detail, read when its screen opens.
@riverpod
Future<OwnerRefund> ownerRefund(Ref ref, String refundId) =>
    ref.watch(ownerRefundsRepositoryProvider).detail(refundId);
