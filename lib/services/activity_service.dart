import 'dart:math';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geolocator;  // ADD THIS PREFIX

import '../models/activity.dart';

class ActivityService {
  static final ActivityService _instance = ActivityService._internal();
  factory ActivityService() => _instance;
  ActivityService._internal();

  final Box<Activity> _activityBox = Hive.box<Activity>('activities');
  Activity? _currentActivity;
  LatLng? _lastPosition;
  double _totalDistance = 0;
  double _maxSpeed = 0;
  double _elevationGain = 0;
  double _lastElevation = 0;

  Activity? get currentActivity => _currentActivity;
  double get currentDistance => _totalDistance;
  double get currentMaxSpeed => _maxSpeed;

  void startNewActivity(String name, ActivityType type, {LatLng? destination}) {
    _currentActivity = Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: type,
      startTime: DateTime.now(),
      routePoints: [],
      destination: destination,
    );

    _totalDistance = 0;
    _maxSpeed = 0;
    _elevationGain = 0;
    _lastElevation = 0;
    _lastPosition = null;
  }

  void addRoutePoint(LatLng position, double speed, double altitude) {
    if (_currentActivity == null) return;

    final point = RoutePoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      speed: speed,
      altitude: altitude,
    );

    _currentActivity!.routePoints.add(point);

    // Calculate distance if we have a previous position
    if (_lastPosition != null) {
      // USE THE PREFIX HERE
      double distance = geolocator.Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      _totalDistance += distance;
      _currentActivity!.distance = _totalDistance;

      // Update max speed
      if (speed > _maxSpeed) {
        _maxSpeed = speed;
        _currentActivity!.maxSpeed = _maxSpeed;
      }

      // Calculate elevation gain
      if (_lastElevation != 0 && altitude > _lastElevation) {
        _elevationGain += (altitude - _lastElevation);
        _currentActivity!.elevationGain = _elevationGain;
      }
    }

    _lastPosition = position;
    _lastElevation = altitude;

    // Update duration and average speed
    _currentActivity!.duration = DateTime.now()
        .difference(_currentActivity!.startTime)
        .inSeconds
        .toDouble();

    if (_currentActivity!.duration > 0) {
      _currentActivity!.averageSpeed = _totalDistance / _currentActivity!.duration;
    }
  }

  Future<void> finishActivity() async {
    if (_currentActivity == null) return;

    _currentActivity!.endTime = DateTime.now();
    _currentActivity!.duration = _currentActivity!.endTime!
        .difference(_currentActivity!.startTime)
        .inSeconds
        .toDouble();

    if (_currentActivity!.duration > 0) {
      _currentActivity!.averageSpeed = _totalDistance / _currentActivity!.duration;
    }

    await _activityBox.put(_currentActivity!.id, _currentActivity!);
    _currentActivity = null;
    _lastPosition = null;
  }

  void cancelActivity() {
    _currentActivity = null;
    _lastPosition = null;
    _totalDistance = 0;
    _maxSpeed = 0;
    _elevationGain = 0;
  }

  List<Activity> getAllActivities() {
    return _activityBox.values.toList().reversed.toList();
  }

  Activity? getActivity(String id) {
    return _activityBox.get(id);
  }

  Map<String, dynamic> getStats() {
    List<Activity> activities = _activityBox.values.toList();

    double totalDistance = 0;
    double totalDuration = 0;
    double totalElevation = 0;
    int totalActivities = activities.length;

    for (var activity in activities) {
      totalDistance += activity.distance;
      totalDuration += activity.duration;
      totalElevation += activity.elevationGain;
    }

    return {
      'totalActivities': totalActivities,
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
      'totalElevation': totalElevation,
      'averageDistance': totalActivities > 0 ? totalDistance / totalActivities : 0,
      'averageDuration': totalActivities > 0 ? totalDuration / totalActivities : 0,
    };
  }
}