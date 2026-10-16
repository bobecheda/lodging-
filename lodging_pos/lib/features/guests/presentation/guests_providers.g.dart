// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guests_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(guestsRepository)
final guestsRepositoryProvider = GuestsRepositoryProvider._();

final class GuestsRepositoryProvider
    extends
        $FunctionalProvider<
          GuestsRepository,
          GuestsRepository,
          GuestsRepository
        >
    with $Provider<GuestsRepository> {
  GuestsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guestsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guestsRepositoryHash();

  @$internal
  @override
  $ProviderElement<GuestsRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GuestsRepository create(Ref ref) {
    return guestsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GuestsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GuestsRepository>(value),
    );
  }
}

String _$guestsRepositoryHash() => r'2587f1ffc3588ebf81803a5edb8d59e16c5f3308';

/// The 30 guests registered or corrected most recently, newest first. A
/// drift `watch()`: updates itself after every register and correction.

@ProviderFor(recentGuests)
final recentGuestsProvider = RecentGuestsProvider._();

/// The 30 guests registered or corrected most recently, newest first. A
/// drift `watch()`: updates itself after every register and correction.

final class RecentGuestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Guest>>,
          List<Guest>,
          Stream<List<Guest>>
        >
    with $FutureModifier<List<Guest>>, $StreamProvider<List<Guest>> {
  /// The 30 guests registered or corrected most recently, newest first. A
  /// drift `watch()`: updates itself after every register and correction.
  RecentGuestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentGuestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentGuestsHash();

  @$internal
  @override
  $StreamProviderElement<List<Guest>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Guest>> create(Ref ref) {
    return recentGuests(ref);
  }
}

String _$recentGuestsHash() => r'b2c0565cd9ebe090092a428836fed3dc676d830f';

/// Matches for what's typed in the search box (empty under 3 characters);
/// also watched, so a correction shows at once.

@ProviderFor(guestSearch)
final guestSearchProvider = GuestSearchFamily._();

/// Matches for what's typed in the search box (empty under 3 characters);
/// also watched, so a correction shows at once.

final class GuestSearchProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Guest>>,
          List<Guest>,
          Stream<List<Guest>>
        >
    with $FutureModifier<List<Guest>>, $StreamProvider<List<Guest>> {
  /// Matches for what's typed in the search box (empty under 3 characters);
  /// also watched, so a correction shows at once.
  GuestSearchProvider._({
    required GuestSearchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'guestSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$guestSearchHash();

  @override
  String toString() {
    return r'guestSearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Guest>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Guest>> create(Ref ref) {
    final argument = this.argument as String;
    return guestSearch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GuestSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$guestSearchHash() => r'8fb0c40c460c171257b75280066c69d463d22144';

/// Matches for what's typed in the search box (empty under 3 characters);
/// also watched, so a correction shows at once.

final class GuestSearchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Guest>>, String> {
  GuestSearchFamily._()
    : super(
        retry: null,
        name: r'guestSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Matches for what's typed in the search box (empty under 3 characters);
  /// also watched, so a correction shows at once.

  GuestSearchProvider call(String text) =>
      GuestSearchProvider._(argument: text, from: this);

  @override
  String toString() => r'guestSearchProvider';
}

/// Other guests registered with [phone] (stored form), for the form's
/// duplicate notice.

@ProviderFor(guestsWithPhone)
final guestsWithPhoneProvider = GuestsWithPhoneFamily._();

/// Other guests registered with [phone] (stored form), for the form's
/// duplicate notice.

final class GuestsWithPhoneProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Guest>>,
          List<Guest>,
          FutureOr<List<Guest>>
        >
    with $FutureModifier<List<Guest>>, $FutureProvider<List<Guest>> {
  /// Other guests registered with [phone] (stored form), for the form's
  /// duplicate notice.
  GuestsWithPhoneProvider._({
    required GuestsWithPhoneFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'guestsWithPhoneProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$guestsWithPhoneHash();

  @override
  String toString() {
    return r'guestsWithPhoneProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<Guest>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Guest>> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return guestsWithPhone(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is GuestsWithPhoneProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$guestsWithPhoneHash() => r'e33db251a221b660bc57abd956baef64c9a9c04b';

/// Other guests registered with [phone] (stored form), for the form's
/// duplicate notice.

final class GuestsWithPhoneFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Guest>>, (String, String?)> {
  GuestsWithPhoneFamily._()
    : super(
        retry: null,
        name: r'guestsWithPhoneProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Other guests registered with [phone] (stored form), for the form's
  /// duplicate notice.

  GuestsWithPhoneProvider call(String phone, String? exceptId) =>
      GuestsWithPhoneProvider._(argument: (phone, exceptId), from: this);

  @override
  String toString() => r'guestsWithPhoneProvider';
}

/// One guest, watched so the opened guest updates after a correction.

@ProviderFor(guestById)
final guestByIdProvider = GuestByIdFamily._();

/// One guest, watched so the opened guest updates after a correction.

final class GuestByIdProvider
    extends $FunctionalProvider<AsyncValue<Guest>, Guest, Stream<Guest>>
    with $FutureModifier<Guest>, $StreamProvider<Guest> {
  /// One guest, watched so the opened guest updates after a correction.
  GuestByIdProvider._({
    required GuestByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'guestByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$guestByIdHash();

  @override
  String toString() {
    return r'guestByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Guest> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Guest> create(Ref ref) {
    final argument = this.argument as String;
    return guestById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GuestByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$guestByIdHash() => r'f73caf357d4c78887788c6c1cd7349bc58596d38';

/// One guest, watched so the opened guest updates after a correction.

final class GuestByIdFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Guest>, String> {
  GuestByIdFamily._()
    : super(
        retry: null,
        name: r'guestByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One guest, watched so the opened guest updates after a correction.

  GuestByIdProvider call(String id) =>
      GuestByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'guestByIdProvider';
}
