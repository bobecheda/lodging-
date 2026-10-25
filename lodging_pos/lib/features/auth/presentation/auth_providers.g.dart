// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(userRepository)
final userRepositoryProvider = UserRepositoryProvider._();

final class UserRepositoryProvider
    extends $FunctionalProvider<UserRepository, UserRepository, UserRepository>
    with $Provider<UserRepository> {
  UserRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userRepositoryHash();

  @$internal
  @override
  $ProviderElement<UserRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UserRepository create(Ref ref) {
    return userRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserRepository>(value),
    );
  }
}

String _$userRepositoryHash() => r'9a414a7acca0a7367a293933818069714401fb66';

@ProviderFor(loginService)
final loginServiceProvider = LoginServiceProvider._();

final class LoginServiceProvider
    extends $FunctionalProvider<LoginService, LoginService, LoginService>
    with $Provider<LoginService> {
  LoginServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loginServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loginServiceHash();

  @$internal
  @override
  $ProviderElement<LoginService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LoginService create(Ref ref) {
    return loginService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LoginService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LoginService>(value),
    );
  }
}

String _$loginServiceHash() => r'16d2db419877395d26d1f22f0ab040fff811856e';

@ProviderFor(ownerPasswordService)
final ownerPasswordServiceProvider = OwnerPasswordServiceProvider._();

final class OwnerPasswordServiceProvider
    extends
        $FunctionalProvider<
          OwnerPasswordService,
          OwnerPasswordService,
          OwnerPasswordService
        >
    with $Provider<OwnerPasswordService> {
  OwnerPasswordServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerPasswordServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerPasswordServiceHash();

  @$internal
  @override
  $ProviderElement<OwnerPasswordService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OwnerPasswordService create(Ref ref) {
    return ownerPasswordService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OwnerPasswordService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OwnerPasswordService>(value),
    );
  }
}

String _$ownerPasswordServiceHash() =>
    r'2f7476b021ffc247e6a3e457796670d09958dbbe';

/// Where first-run setup stands ([SetupState]). Until it is ready, only the
/// setup screen is reachable; once ready, it is unreachable.

@ProviderFor(SetupStatus)
final setupStatusProvider = SetupStatusProvider._();

/// Where first-run setup stands ([SetupState]). Until it is ready, only the
/// setup screen is reachable; once ready, it is unreachable.
final class SetupStatusProvider
    extends $AsyncNotifierProvider<SetupStatus, SetupState> {
  /// Where first-run setup stands ([SetupState]). Until it is ready, only the
  /// setup screen is reachable; once ready, it is unreachable.
  SetupStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'setupStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$setupStatusHash();

  @$internal
  @override
  SetupStatus create() => SetupStatus();
}

String _$setupStatusHash() => r'8072b972fa4aefde95c8f5a7a9bd667f723fd043';

/// Where first-run setup stands ([SetupState]). Until it is ready, only the
/// setup screen is reachable; once ready, it is unreachable.

abstract class _$SetupStatus extends $AsyncNotifier<SetupState> {
  FutureOr<SetupState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SetupState>, SetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SetupState>, SetupState>,
              AsyncValue<SetupState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
