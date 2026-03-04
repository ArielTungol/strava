import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  final List<LocationListener> _listeners = [];

  Position? get currentPosition => _currentPosition;
  LatLng? get currentLatLng => _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : null;

  Future<bool> checkAndRequestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> startTracking({
    required Function(LatLng position) onPositionChanged,
    Function(double distance)? onDistanceChanged,
    Function(double speed)? onSpeedChanged,
  }) async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // Update every 5 meters
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _currentPosition = position;

      // Notify listeners
      onPositionChanged?.call(LatLng(position.latitude, position.longitude));
      onSpeedChanged?.call(position.speed);
    });
  }

  Future<LatLng> getCurrentLocation() async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    _currentPosition = position;
    return LatLng(position.latitude, position.longitude);
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
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