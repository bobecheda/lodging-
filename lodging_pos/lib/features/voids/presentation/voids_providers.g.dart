// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voids_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(voidsRepository)
final voidsRepositoryProvider = VoidsRepositoryProvider._();

final class VoidsRepositoryProvider
    extends
        $FunctionalProvider<VoidsRepository, VoidsRepository, VoidsRepository>
    with $Provider<VoidsRepository> {
  VoidsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voidsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voidsRepositoryHash();

  @$internal
  @override
  $ProviderElement<VoidsRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VoidsRepository create(Ref ref) {
    return voidsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoidsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoidsRepository>(value),
    );
  }
}

String _$voidsRepositoryHash() => r'826a0cc63de376ea743ad5ab193d14b99e7b0ab6';

/// One payment's receipt as the Voids screen shows it, watched: a void
/// shows at once.

@ProviderFor(voidView)
final voidViewProvider = VoidViewFamily._();

/// One payment's receipt as the Voids screen shows it, watched: a void
/// shows at once.

final class VoidViewProvider
    extends
        $FunctionalProvider<AsyncValue<VoidView>, VoidView, Stream<VoidView>>
    with $FutureModifier<VoidView>, $StreamProvider<VoidView> {
  /// One payment's receipt as the Voids screen shows it, watched: a void
  /// shows at once.
  VoidViewProvider._({
    required VoidViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'voidViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$voidViewHash();

  @override
  String toString() {
    return r'voidViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<VoidView> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<VoidView> create(Ref ref) {
    final argument = this.argument as String;
    return voidView(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VoidViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$voidViewHash() => r'1f2ac96e354526c29f0626da4f64ef70c048c017';

/// One payment's receipt as the Voids screen shows it, watched: a void
/// shows at once.

final class VoidViewFamily extends $Family
    with $FunctionalFamilyOverride<Stream<VoidView>, String> {
  VoidViewFamily._()
    : super(
        retry: null,
        name: r'voidViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One payment's receipt as the Voids screen shows it, watched: a void
  /// shows at once.

  VoidViewProvider call(String paymentId) =>
      VoidViewProvider._(argument: paymentId, from: this);

  @override
  String toString() => r'voidViewProvider';
}
