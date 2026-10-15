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

String _$currentShiftHash() => r'eb4505f0c36fa9e74aa419d19ff17073a8bdf4d5';

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

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.

@ProviderFor(ShiftContinued)
final shiftContinuedProvider = ShiftContinuedProvider._();

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.
final class ShiftContinuedProvider
    extends $NotifierProvider<ShiftContinued, bool> {
  /// Whether the signed-in receptionist has continued (or opened) their shift
  /// in this sign-in. Resets on every sign-in, so returning to an open shift
  /// always shows the resume card first.
  ShiftContinuedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shiftContinuedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shiftContinuedHash();

  @$internal
  @override
  ShiftContinued create() => ShiftContinued();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$shiftContinuedHash() => r'cc3f29cc007f479e421e60f0636efb0b657774c6';

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.

abstract class _$ShiftContinued extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Taken so far on [shiftId], for the resume card.

@ProviderFor(shiftTakings)
final shiftTakingsProvider = ShiftTakingsFamily._();

/// Taken so far on [shiftId], for the resume card.

final class ShiftTakingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ShiftTakings>,
          ShiftTakings,
          FutureOr<ShiftTakings>
        >
    with $FutureModifier<ShiftTakings>, $FutureProvider<ShiftTakings> {
  /// Taken so far on [shiftId], for the resume card.
  ShiftTakingsProvider._({
    required ShiftTakingsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shiftTakingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shiftTakingsHash();

  @override
  String toString() {
    return r'shiftTakingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ShiftTakings> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ShiftTakings> create(Ref ref) {
    final argument = this.argument as String;
    return shiftTakings(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShiftTakingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shiftTakingsHash() => r'2c59d1691ff87b19e6c42daa317dad773b53ad42';

/// Taken so far on [shiftId], for the resume card.

final class ShiftTakingsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ShiftTakings>, String> {
  ShiftTakingsFamily._()
    : super(
        retry: null,
        name: r'shiftTakingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Taken so far on [shiftId], for the resume card.

  ShiftTakingsProvider call(String shiftId) =>
      ShiftTakingsProvider._(argument: shiftId, from: this);

  @override
  String toString() => r'shiftTakingsProvider';
}
