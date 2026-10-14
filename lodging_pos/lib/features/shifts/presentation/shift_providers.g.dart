// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shift_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shiftRepository)
final shiftRepositoryProvider = ShiftRepositoryProvider._();

final class ShiftRepositoryProvider
    extends
        $FunctionalProvider<ShiftRepository, ShiftRepository, ShiftRepository>
    with $Provider<ShiftRepository> {
  ShiftRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shiftRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shiftRepositoryHash();

  @$internal
  @override
  $ProviderElement<ShiftRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShiftRepository create(Ref ref) {
    return shiftRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShiftRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShiftRepository>(value),
    );
  }
}

String _$shiftRepositoryHash() => r'a14bc8d89bcd8cb289bb77a3c597ebfae2adc695';

/// The open shift on this device, if any.

@ProviderFor(CurrentShift)
final currentShiftProvider = CurrentShiftProvider._();

/// The open shift on this device, if any.
final class CurrentShiftProvider
    extends $AsyncNotifierProvider<CurrentShift, OpenShift?> {
  /// The open shift on this device, if any.
  CurrentShiftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentShiftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentShiftHash();

  @$internal
  @override
  CurrentShift create() => CurrentShift();
}

String _$currentShiftHash() => r'866efc73489f21550533a2ebecc16921a026f5b3';

/// The open shift on this device, if any.

abstract class _$CurrentShift extends $AsyncNotifier<OpenShift?> {
  FutureOr<OpenShift?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OpenShift?>, OpenShift?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OpenShift?>, OpenShift?>,
              AsyncValue<OpenShift?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
