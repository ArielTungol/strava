// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$locationServiceHash() => r'f7b3dbe3e362693a99dbd0c857f576f80a3f5f74';

/// See also [locationService].
@ProviderFor(locationService)
final locationServiceProvider = AutoDisposeProvider<LocationService>.internal(
  locationService,
  name: r'locationServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$locationServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef LocationServiceRef = AutoDisposeProviderRef<LocationService>;
String _$locationPermissionStateHash() =>
    r'fd3623a1442de75468a5a330532ca163f9021bb7';

/// See also [LocationPermissionState].
@ProviderFor(LocationPermissionState)
final locationPermissionStateProvider =
    AutoDisposeNotifierProvider<LocationPermissionState, bool>.internal(
  LocationPermissionState.new,
  name: r'locationPermissionStateProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$locationPermissionStateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$LocationPermissionState = AutoDisposeNotifier<bool>;
String _$currentLocationHash() => r'b3b760fc086c6d1be9d085789307e241a71f53ed';

/// See also [CurrentLocation].
@ProviderFor(CurrentLocation)
final currentLocationProvider =
    AutoDisposeNotifierProvider<CurrentLocation, LatLng?>.internal(
  CurrentLocation.new,
  name: r'currentLocationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentLocationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentLocation = AutoDisposeNotifier<LatLng?>;
String _$locationTrackingHash() => r'dd87b50b67615f57cb096815ca253263d4623b21';

/// See also [LocationTracking].
@ProviderFor(LocationTracking)
final locationTrackingProvider =
    AutoDisposeNotifierProvider<LocationTracking, bool>.internal(
  LocationTracking.new,
  name: r'locationTrackingProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$locationTrackingHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$LocationTracking = AutoDisposeNotifier<bool>;
String _$currentSpeedHash() => r'c7a079ee5bb57c03b645969a252b0e90cb26d81e';

/// See also [CurrentSpeed].
@ProviderFor(CurrentSpeed)
final currentSpeedProvider =
    AutoDisposeNotifierProvider<CurrentSpeed, double>.internal(
  CurrentSpeed.new,
  name: r'currentSpeedProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$currentSpeedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentSpeed = AutoDisposeNotifier<double>;
String _$locationHistoryHash() => r'8f62afae67743b98ec1e31c29d9c2b58102e3010';

/// See also [LocationHistory].
@ProviderFor(LocationHistory)
final locationHistoryProvider =
    AutoDisposeNotifierProvider<LocationHistory, List<LatLng>>.internal(
  LocationHistory.new,
  name: r'locationHistoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$locationHistoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$LocationHistory = AutoDisposeNotifier<List<LatLng>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
