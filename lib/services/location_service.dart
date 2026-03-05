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

  Position? get currentPosition => _currentPosition;
  LatLng? get currentLatLng => _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : null;

  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('📍 Location services are disabled');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('📍 Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('📍 Location permissions are permanently denied');
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
      print('📍 Got location: ${position.latitude}, ${position.longitude}');
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('📍 Error getting location: $e');
      return null;
    }
  }

  void startTracking({
    required Function(LatLng) onPositionChanged,
    Function(double)? onSpeedChanged,
  }) async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      print('📍 Cannot start tracking - no permission');
      return;
    }

    _positionStream?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // CRITICAL: Updates on EVERY movement, even 0.1 meters!
    );

    _isTracking = true;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      print('📍 Position update: ${position.latitude}, ${position.longitude}, speed: ${position.speed}');
      onPositionChanged(LatLng(position.latitude, position.longitude));
      onSpeedChanged?.call(position.speed);
    }, onError: (error) {
      print('📍 Location stream error: $error');
      _isTracking = false;
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    print('📍 Stopped tracking');
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