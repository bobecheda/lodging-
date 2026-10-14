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

String _$loginServiceHash() => r'adba22c33a822798cdee6c72a72ed1636d5a375b';

/// Whether any user exists. False → only the first-run setup screen is
/// reachable; true → the setup screen is unreachable.

@ProviderFor(SetupStatus)
final setupStatusProvider = SetupStatusProvider._();

/// Whether any user exists. False → only the first-run setup screen is
/// reachable; true → the setup screen is unreachable.
final class SetupStatusProvider
    extends $AsyncNotifierProvider<SetupStatus, bool> {
  /// Whether any user exists. False → only the first-run setup screen is
  /// reachable; true → the setup screen is unreachable.
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

String _$setupStatusHash() => r'208e7d5eb523386129437d1a383628dff0f33e5b';

/// Whether any user exists. False → only the first-run setup screen is
/// reachable; true → the setup screen is unreachable.

abstract class _$SetupStatus extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
