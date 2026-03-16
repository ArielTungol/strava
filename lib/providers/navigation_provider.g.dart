// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$osrmServiceHash() => r'8608dde0b37a2e0567516f6c1219fd7af2426ad9';

/// See also [osrmService].
@ProviderFor(osrmService)
final osrmServiceProvider = AutoDisposeProvider<OSRMService>.internal(
  osrmService,
  name: r'osrmServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$osrmServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef OsrmServiceRef = AutoDisposeProviderRef<OSRMService>;
String _$navigationStateHash() => r'97d35dd06b7f3e4e962e37e1197015f6396d75fb';

/// See also [NavigationState].
@ProviderFor(NavigationState)
final navigationStateProvider = AutoDisposeNotifierProvider<NavigationState,
    AsyncValue<NavigationData>>.internal(
  NavigationState.new,
  name: r'navigationStateProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$navigationStateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NavigationState = AutoDisposeNotifier<AsyncValue<NavigationData>>;
String _$pinnedDestinationHash() => r'e559141cbd72ca56b6ab6d681a1c57fa03297a1f';

/// See also [PinnedDestination].
@ProviderFor(PinnedDestination)
final pinnedDestinationProvider =
    AutoDisposeNotifierProvider<PinnedDestination, LatLng?>.internal(
  PinnedDestination.new,
  name: r'pinnedDestinationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$pinnedDestinationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PinnedDestination = AutoDisposeNotifier<LatLng?>;
String _$navigationUIStateHash() => r'7ef3b3b29415eeac16b1f80da18e11722885a6af';

/// See also [NavigationUIState].
@ProviderFor(NavigationUIState)
final navigationUIStateProvider =
    AutoDisposeNotifierProvider<NavigationUIState, bool>.internal(
  NavigationUIState.new,
  name: r'navigationUIStateProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$navigationUIStateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NavigationUIState = AutoDisposeNotifier<bool>;
String _$turnNotificationHash() => r'1634560a63d05f48cb7e40b818e6b441c69bb066';

/// See also [TurnNotification].
@ProviderFor(TurnNotification)
final turnNotificationProvider = AutoDisposeNotifierProvider<TurnNotification,
    TurnNotificationData?>.internal(
  TurnNotification.new,
  name: r'turnNotificationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$turnNotificationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TurnNotification = AutoDisposeNotifier<TurnNotificationData?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
