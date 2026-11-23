// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'desk_shell.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The desk's destinations, in tab order. Only screens that exist are
/// listed; each story adds its own entry.

@ProviderFor(deskNavItems)
final deskNavItemsProvider = DeskNavItemsProvider._();

/// The desk's destinations, in tab order. Only screens that exist are
/// listed; each story adds its own entry.

final class DeskNavItemsProvider
    extends $FunctionalProvider<List<NavItem>, List<NavItem>, List<NavItem>>
    with $Provider<List<NavItem>> {
  /// The desk's destinations, in tab order. Only screens that exist are
  /// listed; each story adds its own entry.
  DeskNavItemsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deskNavItemsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deskNavItemsHash();

  @$internal
  @override
  $ProviderElement<List<NavItem>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<NavItem> create(Ref ref) {
    return deskNavItems(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<NavItem> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<NavItem>>(value),
    );
  }
}

String _$deskNavItemsHash() => r'a2ccc45636c4e2305c9b1f6d1b4d718bf36b874a';
