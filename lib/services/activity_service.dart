import 'dart:math';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import '../models/activity.dart';
import '../models/route_point.dart';
import '../models/user.dart';

class ActivityService {
  static final ActivityService _instance = ActivityService._internal();
  factory ActivityService() => _instance;
  ActivityService._internal();

  final Box<Activity> _activityBox = Hive.box<Activity>('activities');
  final Box<User> _userBox = Hive.box<User>('user');

  Activity? _currentActivity;
  LatLng? _lastPosition;
  DateTime? _lastTimestamp;
  double _totalDistance = 0;
  double _maxSpeed = 0;
  double _elevationGain = 0;
  double _lastElevation = 0;
  double _currentHeartRate = 0;
  List<double> _heartRateReadings = [];

  // For smoothing speed
  final List<double> _speedBuffer = [];
  static const int speedBufferSize = 5;

  // Splits
  List<Map<String, dynamic>> _splits = [];
  double _lastSplitDistance = 0;
  int _currentSplitIndex = 0;
  static const double splitDistance = 1000; // 1km splits

  // For distance accuracy
  static const double minDistanceDelta = 5.0; // Minimum 5 meters between recorded points

  Activity? get currentActivity => _currentActivity;
  double get currentDistance => _totalDistance;
  double get currentMaxSpeed => _maxSpeed;
  double get currentHeartRate => _currentHeartRate;
  List<Map<String, dynamic>> get splits => _splits;

  void startNewActivity(String name, ActivityType type) {
    _currentActivity = Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: type,
      startTime: DateTime.now(),
      routePoints: [],
      distance: 0,
      duration: 0,
      averageSpeed: 0,
    );

    _resetMetrics();
    print('Activity started: $name, type: $type'); // Debug log
  }

  void _resetMetrics() {
    _totalDistance = 0;
    _maxSpeed = 0;
    _elevationGain = 0;
    _lastElevation = 0;
    _lastPosition = null;
    _lastTimestamp = null;
    _heartRateReadings = [];
    _splits = [];
    _lastSplitDistance = 0;
    _currentSplitIndex = 0;
    _speedBuffer.clear();
  }

  void addRoutePoint(LatLng position, double speed, double altitude, {double? heartRate}) {
    if (_currentActivity == null) {
      print('No current activity, ignoring route point'); // Debug log
      return;
    }

    final now = DateTime.now();

    // Check if we have a last position and if we should record this point
    if (_lastPosition != null) {
      final distance = _calculateDistance(_lastPosition!, position);

      // Skip if not moved enough
      if (distance < minDistanceDelta) {
        // Still update stats but don't add point
        _updateStatsWithoutPoint(position, speed, altitude, distance, now);
        return;
      }
    }

    // Calculate time delta for speed validation
    if (_lastTimestamp != null) {
      final timeDelta = now.difference(_lastTimestamp!).inSeconds;
      if (timeDelta > 0 && _lastPosition != null) {
        final distanceFromLast = _calculateDistance(_lastPosition!, position);
        final calculatedSpeed = distanceFromLast / timeDelta;

        // Use the higher of reported speed and calculated speed
        // but cap unrealistic speeds
        double maxAllowedSpeed = 30.0; // m/s (108 km/h)
        if (_currentActivity!.type == ActivityType.running ||
            _currentActivity!.type == ActivityType.walking) {
          maxAllowedSpeed = 10.0; // 36 km/h max for running/walking
        }

        speed = min(max(calculatedSpeed, speed), maxAllowedSpeed);
      }
    }

    // Smooth speed with moving average
    _speedBuffer.add(speed);
    if (_speedBuffer.length > speedBufferSize) {
      _speedBuffer.removeAt(0);
    }
    final smoothedSpeed = _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length;

    final point = RoutePoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: now,
      speed: smoothedSpeed,
      altitude: altitude,
      heartRate: heartRate ?? _currentHeartRate,
    );

    final updatedRoutePoints = List<RoutePoint>.from(_currentActivity!.routePoints)..add(point);

    _currentActivity = _currentActivity!.copyWith(
      routePoints: updatedRoutePoints,
    );

    if (_lastPosition != null) {
      double distance = _calculateDistance(_lastPosition!, position);

      // Validate distance (can't be negative or extremely large)
      if (distance > 0 && distance < 500) { // Max 500m between points
        _totalDistance += distance;
        _currentActivity = _currentActivity!.copyWith(
          distance: _totalDistance,
        );

        _updateSplits(distance);

        // Update max speed
        if (smoothedSpeed > _maxSpeed) {
          _maxSpeed = smoothedSpeed;
          _currentActivity = _currentActivity!.copyWith(
            maxSpeed: _maxSpeed,
          );
        }

        // Update elevation gain
        if (_lastElevation != 0 && altitude > _lastElevation) {
          _elevationGain += (altitude - _lastElevation);
          _currentActivity = _currentActivity!.copyWith(
            elevationGain: _elevationGain,
          );
        }
      }
    }

    if (heartRate != null) {
      _currentHeartRate = heartRate;
      _heartRateReadings.add(heartRate);

      final averageHeartRate = _heartRateReadings.isNotEmpty
          ? _heartRateReadings.reduce((a, b) => a + b) / _heartRateReadings.length
          : null;
      final maxHeartRate = _heartRateReadings.isNotEmpty
          ? _heartRateReadings.reduce(max)
          : null;

      _currentActivity = _currentActivity!.copyWith(
        averageHeartRate: averageHeartRate,
        maxHeartRate: maxHeartRate,
      );
    }

    _lastPosition = position;
    _lastTimestamp = now;
    _lastElevation = altitude;

    _updateActivityStats();
    print('Route point added. Total distance: $_totalDistance'); // Debug log
  }

  void _updateStatsWithoutPoint(LatLng position, double speed, double altitude, double distance, DateTime now) {
    // Update only stats without adding a route point
    if (_lastPosition != null) {
      _totalDistance += distance;
      _currentActivity = _currentActivity!.copyWith(
        distance: _totalDistance,
      );

      if (speed > _maxSpeed) {
        _maxSpeed = speed;
        _currentActivity = _currentActivity!.copyWith(
          maxSpeed: _maxSpeed,
        );
      }

      if (_lastElevation != 0 && altitude > _lastElevation) {
        _elevationGain += (altitude - _lastElevation);
        _currentActivity = _currentActivity!.copyWith(
          elevationGain: _elevationGain,
        );
      }
    }

    _lastPosition = position;
    _lastTimestamp = now;
    _lastElevation = altitude;

    _updateActivityStats();
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    return geolocator.Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  void _updateSplits(double distance) {
    _lastSplitDistance += distance;

    while (_lastSplitDistance >= splitDistance) {
      final splitTime = DateTime.now().difference(
          _splits.isEmpty
              ? _currentActivity!.startTime
              : DateTime.parse(_splits.last['endTime'])
      ).inSeconds;

      _splits.add({
        'index': _currentSplitIndex++,
        'distance': splitDistance,
        'time': splitTime,
        'pace': splitTime / (splitDistance / 1000),
        'startTime': _splits.isEmpty
            ? _currentActivity!.startTime.toIso8601String()
            : _splits.last['startTime'],
        'endTime': DateTime.now().toIso8601String(),
      });

      _lastSplitDistance -= splitDistance;
    }
  }

  void _updateActivityStats() {
    if (_currentActivity == null) return;

    final duration = DateTime.now()
        .difference(_currentActivity!.startTime)
        .inSeconds
        .toDouble();

    double averageSpeed = 0;
    if (duration > 0 && _totalDistance > 0) {
      averageSpeed = _totalDistance / duration;
    }

    _currentActivity = _currentActivity!.copyWith(
      duration: duration,
      averageSpeed: averageSpeed,
      caloriesBurned: _calculateCalories(),
    );
  }

  int _calculateCalories() {
    if (_currentActivity == null) return 0;

    double met = 5.0;

    switch (_currentActivity!.type) {
      case ActivityType.running:
        met = 8.0 + (_currentActivity!.averageSpeed * 1.5);
        break;
      case ActivityType.walking:
        met = 3.0 + (_currentActivity!.averageSpeed * 0.5);
        break;
      case ActivityType.cycling:
        met = 6.0 + (_currentActivity!.averageSpeed * 2.0);
        break;
      case ActivityType.hiking:
        met = 5.0 + (_currentActivity!.elevationGain ?? 0) / 100;
        break;
      case ActivityType.swimming:
        met = 7.0;
        break;
      case ActivityType.workout:
        met = 6.0;
        break;
    }

    const double weight = 70.0; // Default weight in kg
    final double durationHours = _currentActivity!.duration / 3600;

    return (met * weight * durationHours).round();
  }

  Future<void> finishActivity() async {
    if (_currentActivity == null) {
      print('No current activity to finish'); // Debug log
      return;
    }

    print('Finishing activity...'); // Debug log

    // Add final split if there's remaining distance
    if (_lastSplitDistance > 100) {
      _splits.add({
        'index': _currentSplitIndex++,
        'distance': _lastSplitDistance,
        'time': DateTime.now().difference(
            _splits.isEmpty
                ? _currentActivity!.startTime
                : DateTime.parse(_splits.last['endTime'])
        ).inSeconds,
        'pace': _lastSplitDistance > 0
            ? (DateTime.now().difference(
            _splits.isEmpty
                ? _currentActivity!.startTime
                : DateTime.parse(_splits.last['endTime'])
        ).inSeconds) / (_lastSplitDistance / 1000)
            : 0,
        'startTime': _splits.isEmpty
            ? _currentActivity!.startTime.toIso8601String()
            : _splits.last['startTime'],
        'endTime': DateTime.now().toIso8601String(),
      });
    }

    // Final stats update
    _updateActivityStats();

    _currentActivity = _currentActivity!.copyWith(
      endTime: DateTime.now(),
    );

    print('Saving activity: ${_currentActivity!.id}'); // Debug log
    print('Distance: ${_currentActivity!.distance}, Duration: ${_currentActivity!.duration}'); // Debug log

    // Save to Hive
    await _activityBox.put(_currentActivity!.id, _currentActivity!);

    // Update user stats
    await _updateUserStats();

    // Clear current activity
    _currentActivity = null;
    _resetMetrics();

    print('Activity finished and saved'); // Debug log
  }

  Future<void> _updateUserStats() async {
    if (_userBox.isEmpty) return;

    final user = _userBox.get('current');
    if (user == null) return;

    final updatedUser = user.copyWith(
      totalActivities: user.totalActivities + 1,
      totalDistance: user.totalDistance + _totalDistance,
      totalDuration: user.totalDuration + _currentActivity!.duration.round(),
      totalElevation: user.totalElevation + _elevationGain.round(),
    );

    await _userBox.put('current', updatedUser);
  }

  void cancelActivity() {
    print('Cancelling activity'); // Debug log
    _currentActivity = null;
    _resetMetrics();
  }

  List<Activity> getAllActivities() {
    return _activityBox.values.toList().reversed.toList();
  }

  List<Activity> getActivitiesByType(ActivityType type) {
    return _activityBox.values.where((a) => a.type == type).toList();
  }

  List<Activity> getActivitiesInDateRange(DateTime start, DateTime end) {
    return _activityBox.values
        .where((a) => a.startTime.isAfter(start) && a.startTime.isBefore(end))
        .toList();
  }

  Activity? getActivity(String id) {
    return _activityBox.get(id);
  }

  Future<void> deleteActivity(String id) async {
    await _activityBox.delete(id);
  }

  Future<void> updateActivity(Activity activity) async {
    await _activityBox.put(activity.id, activity);
  }

  Map<String, dynamic> getStats() {
    final activities = _activityBox.values.toList();

    if (activities.isEmpty) {
      return {
        'totalActivities': 0,
        'totalDistance': 0.0,
        'totalDuration': 0.0,
        'totalElevation': 0.0,
        'averageDistance': 0.0,
        'averageDuration': 0.0,
        'averagePace': 0.0,
        'totalCalories': 0,
        'longestRun': 0.0,
        'longestRide': 0.0,
        'fastestRun': 0.0,
        'fastestRide': 0.0,
      };
    }

    double totalDistance = 0;
    double totalDuration = 0;
    double totalElevation = 0;
    int totalCalories = 0;
    double longestRun = 0;
    double longestRide = 0;
    double fastestRun = double.infinity;
    double fastestRide = 0;

    for (var activity in activities) {
      totalDistance += activity.distance;
      totalDuration += activity.duration;
      totalElevation += activity.elevationGain ?? 0;
      totalCalories += activity.caloriesBurned;

      if (activity.type == ActivityType.running) {
        if (activity.distance > longestRun) longestRun = activity.distance;
        final pace = activity.duration / (activity.distance / 1000);
        if (pace < fastestRun) fastestRun = pace;
      }

      if (activity.type == ActivityType.cycling) {
        if (activity.distance > longestRide) longestRide = activity.distance;
        final speed = activity.averageSpeed * 3.6;
        if (speed > fastestRide) fastestRide = speed;
      }
    }

    return {
      'totalActivities': activities.length,
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
      'totalElevation': totalElevation,
      'averageDistance': totalDistance / activities.length,
      'averageDuration': totalDuration / activities.length,
      'averagePace': totalDistance > 0 ? (totalDuration / 60) / (totalDistance / 1000) : 0,
      'totalCalories': totalCalories,
      'longestRun': longestRun,
      'longestRide': longestRide,
      'fastestRun': fastestRun != double.infinity ? fastestRun : 0,
      'fastestRide': fastestRide,
      'byType': {
        'running': activities.where((a) => a.type == ActivityType.running).length,
        'walking': activities.where((a) => a.type == ActivityType.walking).length,
        'cycling': activities.where((a) => a.type == ActivityType.cycling).length,
        'hiking': activities.where((a) => a.type == ActivityType.hiking).length,
        'swimming': activities.where((a) => a.type == ActivityType.swimming).length,
        'workout': activities.where((a) => a.type == ActivityType.workout).length,
      }
    };
  }
}