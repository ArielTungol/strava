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
  double _totalDistance = 0;
  double _maxSpeed = 0;
  double _elevationGain = 0;
  double _lastElevation = 0;
  double _currentHeartRate = 0;
  List<double> _heartRateReadings = [];

  // Splits
  List<Map<String, dynamic>> _splits = [];
  double _lastSplitDistance = 0;
  int _currentSplitIndex = 0;
  static const double splitDistance = 1000;

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
  }

  void _resetMetrics() {
    _totalDistance = 0;
    _maxSpeed = 0;
    _elevationGain = 0;
    _lastElevation = 0;
    _lastPosition = null;
    _heartRateReadings = [];
    _splits = [];
    _lastSplitDistance = 0;
    _currentSplitIndex = 0;
  }

  void addRoutePoint(LatLng position, double speed, double altitude, {double? heartRate}) {
    if (_currentActivity == null) return;

    final point = RoutePoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      speed: speed,
      altitude: altitude,
      heartRate: heartRate ?? _currentHeartRate,
    );

    final updatedRoutePoints = List<RoutePoint>.from(_currentActivity!.routePoints)..add(point);

    _currentActivity = _currentActivity!.copyWith(
      routePoints: updatedRoutePoints,
    );

    if (_lastPosition != null) {
      double distance = geolocator.Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      _totalDistance += distance;
      _currentActivity = _currentActivity!.copyWith(
        distance: _totalDistance,
      );

      _updateSplits(distance);

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
    _lastElevation = altitude;

    _updateActivityStats();
  }

  void _updateSplits(double distance) {
    _lastSplitDistance += distance;

    if (_lastSplitDistance >= splitDistance) {
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
            : _splits.last['endTime'],
        'endTime': DateTime.now().toIso8601String(),
      });

      _lastSplitDistance = _lastSplitDistance - splitDistance;
    }
  }

  void _updateActivityStats() {
    if (_currentActivity == null) return;

    final duration = DateTime.now()
        .difference(_currentActivity!.startTime)
        .inSeconds
        .toDouble();

    double averageSpeed = 0;
    if (duration > 0) {
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

    const double weight = 70.0;
    final double durationHours = _currentActivity!.duration / 3600;

    return (met * weight * durationHours).round();
  }

  Future<void> finishActivity() async {
    if (_currentActivity == null) return;

    _currentActivity = _currentActivity!.copyWith(
      endTime: DateTime.now(),
    );

    _updateActivityStats();

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
            : _splits.last['endTime'],
        'endTime': DateTime.now().toIso8601String(),
      });
    }

    await _activityBox.put(_currentActivity!.id, _currentActivity!);

    await _updateUserStats();

    _currentActivity = null;
    _lastPosition = null;
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