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
  DateTime? _startTime;

  Activity? get currentActivity => _currentActivity;

  // Initialize boxes
  void _initBoxes() {
    try {
      _activityBox = Hive.box<Activity>('activities');
      _userBox = Hive.box<User>('user');
      print('✅ ActivityService: Boxes initialized');
    } catch (e) {
      print('❌ ActivityService: Error initializing boxes: $e');
    }
  }

  void startNewActivity(String name, ActivityType type) {
    print('\n========== ACTIVITY SERVICE: START ==========');

    _initBoxes();

    _startTime = DateTime.now();
    _totalDistance = 0;
    _maxSpeed = 0;
    _routePoints = [];
    _lastPosition = null;

    _currentActivity = Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: type,
      startTime: _startTime!,
      routePoints: [],
      distance: 0,
      duration: 0,
      averageSpeed: 0,
      maxSpeed: 0,
      caloriesBurned: 0,
    );

    print('✅ Activity created:');
    print('  - ID: ${_currentActivity!.id}');
    print('  - Name: ${_currentActivity!.name}');
    print('  - Type: ${_currentActivity!.type}');
    print('  - Start Time: ${_currentActivity!.startTime}');
    print('========== ACTIVITY SERVICE: START COMPLETE ==========\n');
  }

  void addRoutePoint(LatLng position, double speed, double altitude) {
    if (_currentActivity == null) {
      print('⚠️ No current activity, ignoring route point');
      return;
    }

    final now = DateTime.now();

    // Create route point
    final point = RoutePoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: now,
      speed: speed,
      altitude: altitude,
    );

    _routePoints.add(point);

    // Calculate distance if we have a previous position
    if (_lastPosition != null) {
      double distance = geolocator.Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance > 0 && distance < 500) { // Sanity check
        _totalDistance += distance;

        if (speed > _maxSpeed) {
          _maxSpeed = speed;
        }
      }
    }

    _lastPosition = position;

    // Calculate duration and average speed
    final duration = now.difference(_startTime!).inSeconds.toDouble();
    double averageSpeed = duration > 0 ? _totalDistance / duration : 0;

    // Update current activity
    _currentActivity = _currentActivity!.copyWith(
      routePoints: List.from(_routePoints),
      distance: _totalDistance,
      duration: duration,
      averageSpeed: averageSpeed,
      maxSpeed: _maxSpeed,
      caloriesBurned: _calculateCalories(duration, averageSpeed),
    );

    if (_routePoints.length % 10 == 0) { // Print every 10 points
      print('📍 Route points: ${_routePoints.length}, Distance: ${_totalDistance.toStringAsFixed(1)}m');
    }
  }

  int _calculateCalories(double durationSeconds, double speed) {
    // Simple calories calculation: ~0.1 kcal per meter for running
    return (_totalDistance * 0.1).round();
  }

  Future<void> finishActivity() async {
    print('\n========== ACTIVITY SERVICE: FINISH ==========');

    if (_currentActivity == null) {
      print('❌ No current activity to finish');
      return;
    }

    try {
      _initBoxes();

      // Set end time
      final now = DateTime.now();
      final duration = now.difference(_startTime!).inSeconds.toDouble();

      _currentActivity = _currentActivity!.copyWith(
        endTime: now,
        duration: duration,
        routePoints: List.from(_routePoints),
      );

      print('✅ Finishing activity:');
      print('  - ID: ${_currentActivity!.id}');
      print('  - Name: ${_currentActivity!.name}');
      print('  - Distance: ${_currentActivity!.distance.toStringAsFixed(1)} meters');
      print('  - Duration: ${_currentActivity!.duration.toStringAsFixed(0)} seconds');
      print('  - Route points: ${_currentActivity!.routePoints.length}');
      print('  - End Time: ${_currentActivity!.endTime}');

      // Save to Hive
      print('💾 Saving to Hive...');
      await _activityBox.put(_currentActivity!.id, _currentActivity!);
      print('✅ Activity saved to Hive');

      // Verify save
      final savedActivity = _activityBox.get(_currentActivity!.id);
      if (savedActivity != null) {
        print('✅ Verification: Activity found in Hive');
        print('  - Saved ID: ${savedActivity.id}');
        print('  - Saved Name: ${savedActivity.name}');
      }

      // Clear current activity
      _currentActivity = null;
      _routePoints.clear();
      _totalDistance = 0;
      _maxSpeed = 0;
      _lastPosition = null;
      _startTime = null;

      print('✅ Activity finished and saved successfully');

    } catch (e) {
      print('❌ Error saving activity: $e');
      print('❌ Error type: ${e.runtimeType}');
    }

    print('========== ACTIVITY SERVICE: FINISH COMPLETE ==========\n');
  }

  void cancelActivity() {
    print('\n========== ACTIVITY SERVICE: CANCEL ==========');
    _currentActivity = null;
    _routePoints.clear();
    _totalDistance = 0;
    _maxSpeed = 0;
    _lastPosition = null;
    _startTime = null;
    print('✅ Activity cancelled');
    print('========== ACTIVITY SERVICE: CANCEL COMPLETE ==========\n');
  }

  List<Activity> getAllActivities() {
    try {
      _initBoxes();
      final activities = _activityBox.values.toList().reversed.toList();
      print('\n📋 HISTORY: Found ${activities.length} activities');
      for (var i = 0; i < activities.length; i++) {
        print('  📋 [${i + 1}] ${activities[i].name} - ${activities[i].formattedDistance}');
      }
      return activities;
    } catch (e) {
      print('❌ Error getting activities: $e');
      return [];
    }
  }
}