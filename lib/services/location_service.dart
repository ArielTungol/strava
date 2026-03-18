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
  }) async {
    bool hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return;

    _positionStream?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2, // Update every 2 meters
    );

    _isTracking = true;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      onPositionChanged(LatLng(position.latitude, position.longitude));
      onSpeedChanged?.call(position.speed);
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
}