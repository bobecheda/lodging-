// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The signed-in user, held in memory only. Null when signed out.

@ProviderFor(Session)
final sessionProvider = SessionProvider._();

/// The signed-in user, held in memory only. Null when signed out.
final class SessionProvider extends $NotifierProvider<Session, UserAccount?> {
  /// The signed-in user, held in memory only. Null when signed out.
  SessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionHash();

  @$internal
  @override
  Session create() => Session();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserAccount? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserAccount?>(value),
    );
  }
}

String _$sessionHash() => r'c632a7d7e23d0ce113231aaabbf55525e0fba3fd';

/// The signed-in user, held in memory only. Null when signed out.

abstract class _$Session extends $Notifier<UserAccount?> {
  UserAccount? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UserAccount?, UserAccount?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UserAccount?, UserAccount?>,
              UserAccount?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
