import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  final List<LocationListener> _listeners = [];
  bool _isTracking = false;

  Position? get currentPosition => _currentPosition;
  LatLng? get currentLatLng => _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : null;

  // Check and request permissions with better error handling
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  // Start tracking with better error handling
  Future<void> startTracking({
    required Function(LatLng position) onPositionChanged,
    Function(double distance)? onDistanceChanged,
    Function(double speed)? onSpeedChanged,
  }) async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    // Cancel existing stream if any
    _positionStream?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // Update every 5 meters
      timeLimit: Duration(seconds: 10), // Add timeout to prevent hanging
    );

    _isTracking = true;

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .handleError((error) {
      print('Location stream error: $error');
      _isTracking = false;
    })
        .listen((Position position) {
      _currentPosition = position;

      // Notify listeners
      onPositionChanged?.call(LatLng(position.latitude, position.longitude));
      onSpeedChanged?.call(position.speed);

      // Calculate distance if previous position exists
      if (onDistanceChanged != null && _lastPosition != null) {
        double distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        onDistanceChanged(distance);
      }

      _lastPosition = position;
    });
  }

  Position? _lastPosition;

  // Get current location once with timeout
  Future<LatLng?> getCurrentLocation() async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      _currentPosition = position;
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
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

  void addListener(LocationListener listener) {
    _listeners.add(listener);
  }

  void removeListener(LocationListener listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    stopTracking();
    _listeners.clear();
  }
}

abstract class LocationListener {
  void onLocationChanged(LatLng position);
  void onSpeedChanged(double speed);
}