import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/clock.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../../core/settings/settings_repository.dart';
import '../domain/idle_lock.dart';

part 'idle_lock.g.dart';

/// How often to check for inactivity while someone is signed in. Tests
/// override it with null and call [IdleLock.check] themselves.
@Riverpod(keepAlive: true)
Duration? idleCheckInterval(Ref ref) => const Duration(seconds: 15);

/// Why the screen was last locked, so the login screen can say so.
sealed class LockNotice {
  const LockNotice();
}

/// Locked automatically after [minutes] idle (`user.auto_lock`).
class IdleLockNotice extends LockNotice {
  const IdleLockNotice(this.minutes);
  final int minutes;
}

/// Locked with the sidebar's "Lock screen" button (`user.lock`).
class ManualLockNotice extends LockNotice {
  const ManualLockNotice();
}

/// Locks the screen: signs the user out after `idle_lock_minutes` without
/// activity, or at once via [lockNow]. The shift stays open; only the
/// session ends. Idle and manual locks are audited separately, so the trail
/// shows which one happened.
///
/// State: why the screen was last locked; null after a fresh sign-in.
@Riverpod(keepAlive: true)
class IdleLock extends _$IdleLock {
  DateTime? _lastActivity;
  Timer? _timer;
  var _locking = false;

  @override
  LockNotice? build() {
    ref.listen(sessionProvider, (previous, next) {
      if (next == null) {
        _stop();
      } else if (previous?.id != next.id) {
        state = null; // A new sign-in clears the last lock message.
        _start();
      }
    });
    ref.onDispose(_stop);
    // Created mid-session: count from now.
    if (ref.read(sessionProvider) != null) _start();
    return null;
  }

  @visibleForTesting
  DateTime? get lastActivity => _lastActivity;

  /// Any click, scroll, key press or mouse movement.
  void recordActivity() => _lastActivity = ref.read(clockProvider).now();

  void _start() {
    recordActivity();
    _timer?.cancel();
    final interval = ref.read(idleCheckIntervalProvider);
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => unawaited(check()));
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _lastActivity = null;
  }

  /// Locks if the signed-in user has been idle long enough. Overlapping
  /// calls do nothing while one is running, so a lock is audited once.
  Future<void> check() async {
    if (_locking || _lastActivity == null) return;
    final user = ref.read(sessionProvider);
    if (user == null) return;

    _locking = true;
    try {
      final minutes = idleLockMinutesFrom(
        await ref
            .read(settingsRepositoryProvider)
            .value(SettingKeys.idleLockMinutes),
      );
      // Re-read after the await: activity or a sign-out may have happened.
      final last = _lastActivity;
      if (last == null || ref.read(sessionProvider)?.id != user.id) return;
      final now = ref.read(clockProvider).now();
      if (!shouldLock(lastActivity: last, now: now, idleMinutes: minutes)) {
        return;
      }

      await _lock(
        user.id,
        action: 'user.auto_lock',
        details: {'idle_minutes': minutes},
        notice: IdleLockNotice(minutes),
      );
    } finally {
      _locking = false;
    }
  }

  /// Locks the screen now ("Lock screen" button), audited as `user.lock`.
  Future<void> lockNow() async {
    final user = ref.read(sessionProvider);
    if (user == null || _locking) return;
    _locking = true;
    try {
      await _lock(
        user.id,
        action: 'user.lock',
        notice: const ManualLockNotice(),
      );
    } finally {
      _locking = false;
    }
  }

  Future<void> _lock(
    String userId, {
    required String action,
    Map<String, Object?> details = const {},
    required LockNotice notice,
  }) async {
    try {
      await ref
          .read(auditWriterProvider)
          .recordEvent(
            action: action,
            userId: userId,
            entity: 'users',
            entityId: userId,
            details: details,
          );
    } catch (error, stack) {
      // Lock anyway: an unattended desk matters more than the audit row.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'lock'),
      );
    }
    ref.read(sessionProvider.notifier).signOut();
    state = notice;
  }
}
