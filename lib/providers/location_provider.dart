import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../services/activity_service.dart';
import 'activity_provider.dart';

part 'location_provider.g.dart';

@riverpod
LocationService locationService(LocationServiceRef ref) {
  return LocationService();
}

@riverpod
class LocationPermissionState extends _$LocationPermissionState {
  @override
  bool build() {
    return false;
  }

  Future<bool> checkAndRequestPermission() async {
    final service = ref.read(locationServiceProvider);
    final hasPermission = await service.checkAndRequestPermission();
    state = hasPermission;
    return hasPermission;
  }
}

@riverpod
class CurrentLocation extends _$CurrentLocation {
  @override
  LatLng? build() {
    return null;
  }

  void updateLocation(LatLng location) {
    state = location;
  }

  void clearLocation() {
    state = null;
  }
}

@riverpod
class LocationTracking extends _$LocationTracking {
  @override
  bool build() {
    return false;
  }

  Future<void> startTracking() async {
    final service = ref.read(locationServiceProvider);
    final hasPermission = await ref.read(locationPermissionStateProvider.notifier).checkAndRequestPermission();

    if (!hasPermission) {
      state = false;
      return;
    }

    state = true;

    service.startTracking(
      onPositionChanged: (position) {
        ref.read(currentLocationProvider.notifier).updateLocation(position);

        final currentActivity = ref.read(currentActivityProvider);
        if (currentActivity != null) {
          final speed = service.currentPosition?.speed ?? 0;
          ref.read(activityServiceProvider).addRoutePoint(position, speed, 0);
          ref.read(currentActivityProvider.notifier).updateActivity();
        }
      },
      onSpeedChanged: (speed) {
        ref.read(currentSpeedProvider.notifier).updateSpeed(speed);
      },
    );
  }

  void stopTracking() {
    final service = ref.read(locationServiceProvider);
    service.stopTracking();
    state = false;
  }
}

@riverpod
class CurrentSpeed extends _$CurrentSpeed {
  @override
  double build() {
    return 0.0;
  }

  void updateSpeed(double speed) {
    state = speed;
  }

  void resetSpeed() {
    state = 0.0;
  }
}

@riverpod
class LocationHistory extends _$LocationHistory {
  @override
  List<LatLng> build() {
    return [];
  }

  void addPoint(LatLng point) {
    state = [...state, point];
  }

  void clearHistory() {
    state = [];
  }
}