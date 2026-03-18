import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  bool _isTracking = false;

  // For accuracy filtering
  double _lastAccuracy = 0;
  static const double minAccuracy = 20.0; // Minimum acceptable accuracy in meters
  static const double minDistanceDelta = 5.0; // Minimum distance change to record point

  Position? get currentPosition => _currentPosition;
  LatLng? get currentLatLng => _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : null;

  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<LatLng?> getCurrentLocation() async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return null;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      _currentPosition = position;
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  void startTracking({
    required Function(LatLng) onPositionChanged,
    Function(double)? onSpeedChanged,
    Function(double)? onDistanceChanged,
  }) async {
    _positionStream?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // We'll filter manually for better control
      timeLimit: Duration(seconds: 10),
    );

    _isTracking = true;
    _lastAccuracy = 0;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      // Filter by accuracy
      if (position.accuracy > minAccuracy) {
        return; // Skip inaccurate points
      }

      // Filter by minimum distance if we have a previous position
      if (_currentPosition != null) {
        double distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        if (distance < minDistanceDelta) {
          return; // Skip if not moved enough
        }
      }

      _currentPosition = position;
      _lastAccuracy = position.accuracy;

      onPositionChanged(LatLng(position.latitude, position.longitude));
      onSpeedChanged?.call(position.speed);

      // Calculate and report distance since last point
      if (_currentPosition != null) {
        double distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        onDistanceChanged?.call(distance);
      }

    }, onError: (error) {
      _isTracking = false;
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
  }

  double calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  bool get isTracking => _isTracking;

  void dispose() {
    stopTracking();
  }
}