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

  late final Box<Activity> _activityBox;
  late final Box<User> _userBox;

  Activity? _currentActivity;
  LatLng? _lastPosition;
  double _totalDistance = 0;
  double _maxSpeed = 0;
  List<RoutePoint> _routePoints = [];

  Activity? get currentActivity => _currentActivity;

  // Initialize boxes
  void _initBoxes() {
    _activityBox = Hive.box<Activity>('activities');
    _userBox = Hive.box<User>('user');
    print('✅ Boxes initialized');
  }

  void startNewActivity(String name, ActivityType type) {
    _initBoxes();

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

    _totalDistance = 0;
    _maxSpeed = 0;
    _routePoints = [];
    _lastPosition = null;

    print('✅ Activity started: ${_currentActivity!.id}');
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

    _routePoints.add(point);

    if (_lastPosition != null) {
      double distance = geolocator.Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      _totalDistance += distance;

      if (speed > _maxSpeed) {
        _maxSpeed = speed;
      }
    }

    _lastPosition = position;

    // Update current activity
    final duration = DateTime.now().difference(_currentActivity!.startTime).inSeconds.toDouble();
    double averageSpeed = duration > 0 ? _totalDistance / duration : 0;

    _currentActivity = _currentActivity!.copyWith(
      routePoints: List.from(_routePoints),
      distance: _totalDistance,
      duration: duration,
      averageSpeed: averageSpeed,
      maxSpeed: _maxSpeed,
      caloriesBurned: _calculateCalories(duration, averageSpeed),
    );
  }

  int _calculateCalories(double duration, double speed) {
    // Simple calories calculation
    return (speed * duration * 0.1).round();
  }

  Future<void> finishActivity() async {
    print('========== FINISHING ACTIVITY ==========');

    if (_currentActivity == null) {
      print('❌ No activity to finish');
      return;
    }

    try {
      _initBoxes();

      // Set end time
      _currentActivity = _currentActivity!.copyWith(
        endTime: DateTime.now(),
      );

      print('✅ Saving activity: ${_currentActivity!.id}');
      print('✅ Distance: ${_currentActivity!.distance} meters');
      print('✅ Route points: ${_currentActivity!.routePoints.length}');

      // Save to Hive
      await _activityBox.put(_currentActivity!.id, _currentActivity!);
      print('✅ Activity saved to Hive');

      // Verify save
      final saved = _activityBox.get(_currentActivity!.id);
      if (saved != null) {
        print('✅ Verification: Activity found in Hive');
      }

      // Clear current activity
      _currentActivity = null;
      _routePoints.clear();
      _totalDistance = 0;
      _maxSpeed = 0;
      _lastPosition = null;

      print('✅ Activity finished successfully');
      print('=======================================');

    } catch (e) {
      print('❌ Error saving activity: $e');
    }
  }

  void cancelActivity() {
    _currentActivity = null;
    _routePoints.clear();
    _totalDistance = 0;
    _maxSpeed = 0;
    _lastPosition = null;
    print('✅ Activity cancelled');
  }

  List<Activity> getAllActivities() {
    try {
      _initBoxes();
      final activities = _activityBox.values.toList().reversed.toList();
      print('📋 Found ${activities.length} activities in history');
      return activities;
    } catch (e) {
      print('❌ Error getting activities: $e');
      return [];
    }
  }
}