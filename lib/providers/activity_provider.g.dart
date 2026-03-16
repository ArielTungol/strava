// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activityServiceHash() => r'5eb91f85b57fb3a5a03b1ff62d1c99b3395efdc9';

/// See also [activityService].
@ProviderFor(activityService)
final activityServiceProvider = AutoDisposeProvider<ActivityService>.internal(
  activityService,
  name: r'activityServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$activityServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ActivityServiceRef = AutoDisposeProviderRef<ActivityService>;
String _$activitiesListHash() => r'f6d65b3ac4fb67d0a5847a66e010f84519b40019';

/// See also [activitiesList].
@ProviderFor(activitiesList)
final activitiesListProvider =
    AutoDisposeFutureProvider<List<Activity>>.internal(
  activitiesList,
  name: r'activitiesListProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$activitiesListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ActivitiesListRef = AutoDisposeFutureProviderRef<List<Activity>>;
String _$currentActivityHash() => r'91598f7e30a21852ebfb52b38c501c3a9a3c905b';

/// See also [CurrentActivity].
@ProviderFor(CurrentActivity)
final currentActivityProvider =
    AutoDisposeNotifierProvider<CurrentActivity, Activity?>.internal(
  CurrentActivity.new,
  name: r'currentActivityProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentActivityHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentActivity = AutoDisposeNotifier<Activity?>;
String _$selectedActivityHash() => r'ae75dd3715d4b8eda0a9d41aad446c66cc9023e1';

/// See also [SelectedActivity].
@ProviderFor(SelectedActivity)
final selectedActivityProvider =
    AutoDisposeNotifierProvider<SelectedActivity, Activity?>.internal(
  SelectedActivity.new,
  name: r'selectedActivityProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$selectedActivityHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SelectedActivity = AutoDisposeNotifier<Activity?>;
String _$activityStatsHash() => r'd7efd21a12ed643c2b43cc0f18891c41a437a2d5';

/// See also [ActivityStats].
@ProviderFor(ActivityStats)
final activityStatsProvider = AutoDisposeAsyncNotifierProvider<ActivityStats,
    Map<String, dynamic>>.internal(
  ActivityStats.new,
  name: r'activityStatsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$activityStatsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ActivityStats = AutoDisposeAsyncNotifier<Map<String, dynamic>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
