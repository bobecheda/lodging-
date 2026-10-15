// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'idle_lock.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How often to check for inactivity while someone is signed in. Tests
/// override it with null and call [IdleLock.check] themselves.

@ProviderFor(idleCheckInterval)
final idleCheckIntervalProvider = IdleCheckIntervalProvider._();

/// How often to check for inactivity while someone is signed in. Tests
/// override it with null and call [IdleLock.check] themselves.

final class IdleCheckIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// How often to check for inactivity while someone is signed in. Tests
  /// override it with null and call [IdleLock.check] themselves.
  IdleCheckIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'idleCheckIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$idleCheckIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return idleCheckInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$idleCheckIntervalHash() => r'b2824bf341ea48c5e5a79b0069afb6c06ad7ab70';

/// Locks the screen: signs the user out after `idle_lock_minutes` without
/// activity, or at once via [lockNow]. The shift stays open; only the
/// session ends. Idle and manual locks are audited separately, so the trail
/// shows which one happened.
///
/// State: why the screen was last locked; null after a fresh sign-in.

@ProviderFor(IdleLock)
final idleLockProvider = IdleLockProvider._();

/// Locks the screen: signs the user out after `idle_lock_minutes` without
/// activity, or at once via [lockNow]. The shift stays open; only the
/// session ends. Idle and manual locks are audited separately, so the trail
/// shows which one happened.
///
/// State: why the screen was last locked; null after a fresh sign-in.
final class IdleLockProvider extends $NotifierProvider<IdleLock, LockNotice?> {
  /// Locks the screen: signs the user out after `idle_lock_minutes` without
  /// activity, or at once via [lockNow]. The shift stays open; only the
  /// session ends. Idle and manual locks are audited separately, so the trail
  /// shows which one happened.
  ///
  /// State: why the screen was last locked; null after a fresh sign-in.
  IdleLockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'idleLockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$idleLockHash();

  @$internal
  @override
  IdleLock create() => IdleLock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LockNotice? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LockNotice?>(value),
    );
  }
}

String _$idleLockHash() => r'5bba90684c87ba5d291c430dda34631034961bb1';

/// Locks the screen: signs the user out after `idle_lock_minutes` without
/// activity, or at once via [lockNow]. The shift stays open; only the
/// session ends. Idle and manual locks are audited separately, so the trail
/// shows which one happened.
///
/// State: why the screen was last locked; null after a fresh sign-in.

abstract class _$IdleLock extends $Notifier<LockNotice?> {
  LockNotice? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LockNotice?, LockNotice?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LockNotice?, LockNotice?>,
              LockNotice?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
