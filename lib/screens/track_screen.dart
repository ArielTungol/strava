import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geolocator;

import '../services/location_service.dart';
import '../services/osrm_service.dart';
import '../services/activity_service.dart';
import '../models/activity.dart';

class TrackScreen extends StatefulWidget {
  final LatLng? currentLocation;

  const TrackScreen({super.key, this.currentLocation});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final ActivityService _activityService = ActivityService();

  // Current location tracking
  LatLng? _currentPosition;
  LatLng? _previousPosition;
  double _heading = 0.0;
  LatLng? _destination;

  // Route data
  List<LatLng> _fullRoute = [];
  List<LatLng> _trackedRoute = [];
  List<Map<String, dynamic>> _routeInstructions = [];
  List<Map<String, dynamic>> _nearbyLandmarks = [];

  // Navigation state
  bool _isTracking = false;
  bool _isSelectingDestination = false;
  bool _isNavigating = false;
  String _selectedTravelMode = 'driving';
  bool _locationPermissionGranted = false;
  bool _isLoadingLocation = true;
  String _locationError = '';

  // Bottom sheet state
  bool _showRouteSheet = false;
  bool _showLandmarksSheet = false;

  // Arrival detection
  bool _hasArrived = false;
  final double _arrivalThreshold = 20.0;
  bool _arrivalNotified = false;

  // Navigation info
  String _nextInstruction = "";
  double _distanceToNextTurn = 0;
  String _formattedDistanceToTurn = "";
  double _totalDistance = 0;
  double _totalDuration = 0;
  String _formattedEta = "";
  String _formattedTotalDistance = "";
  String _formattedTotalDuration = "";
  List<Map<String, dynamic>> _routeSegments = [];

  // Live tracking metrics
  double _currentSpeed = 0;
  double _currentDistance = 0;
  double _currentDuration = 0;
  double _maxSpeed = 0;
  double _averageSpeed = 0;
  String _formattedPace = "--:--";

  // For tracking movement with drift protection
  LatLng? _lastPositionForDistance;
  DateTime? _lastTimeForSpeed;
  final double _minMovementThreshold = 2.0;
  int _stationaryCount = 0;
  LatLng? _stablePosition;

  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();

  // Animation for smooth marker movement
  AnimationController? _markerAnimationController;
  LatLng? _targetPosition;
  LatLng? _currentAnimatedPosition;

  static const int updateIntervalMs = 100;
  static const int markerAnimationDurationMs = 500;

  final Map<String, IconData> _travelModeIcons = {
    'driving': Icons.directions_car,
    'walking': Icons.directions_walk,
    'cycling': Icons.directions_bike,
  };

  final Map<String, Color> _travelModeColors = {
    'driving': Colors.blue,
    'walking': Colors.green,
    'cycling': Colors.orange,
  };

  // Mock nearby landmarks
  final List<Map<String, dynamic>> _mockLandmarks = [
    {'name': 'WalterMart Arayat', 'type': 'mall', 'distance': '0.2 km', 'icon': Icons.shopping_bag},
    {'name': '1st Honor Pasalubong', 'type': 'shop', 'distance': '0.3 km', 'icon': Icons.shop},
    {'name': 'Kapet Silim - ARAYAT', 'type': 'cafe', 'distance': '0.4 km', 'icon': Icons.local_cafe},
    {'name': 'Project Ohms Vape Shop', 'type': 'shop', 'distance': '0.5 km', 'icon': Icons.shop},
    {'name': "McDonald's Arayat", 'type': 'restaurant', 'distance': '0.6 km', 'icon': Icons.restaurant},
    {'name': 'MR. DIY', 'type': 'shop', 'distance': '0.7 km', 'icon': Icons.shop},
    {'name': 'Irrigation Canal', 'type': 'landmark', 'distance': '0.8 km', 'icon': Icons.location_city},
    {'name': 'Adabbia', 'type': 'restaurant', 'distance': '0.9 km', 'icon': Icons.restaurant},
    {'name': 'Puregold Arayat', 'type': 'mall', 'distance': '1.0 km', 'icon': Icons.shopping_bag},
    {'name': 'Honda Motor Sports', 'type': 'shop', 'distance': '1.1 km', 'icon': Icons.shop},
    {'name': 'Cemetery', 'type': 'landmark', 'distance': '1.2 km', 'icon': Icons.location_city},
    {'name': 'Soupy Buns', 'type': 'restaurant', 'distance': '1.3 km', 'icon': Icons.restaurant},
    {'name': 'Kiri Café', 'type': 'cafe', 'distance': '1.4 km', 'icon': Icons.local_cafe},
    {'name': 'Yamaha 3S Shop', 'type': 'shop', 'distance': '1.5 km', 'icon': Icons.shop},
    {'name': 'Arayat Public Market', 'type': 'market', 'distance': '1.6 km', 'icon': Icons.store},
    {'name': 'Riverside St', 'type': 'street', 'distance': '1.7 km', 'icon': Icons.add_road_outlined},
    {'name': 'Richsun Home Center', 'type': 'shop', 'distance': '1.8 km', 'icon': Icons.shop},
    {'name': 'CityMall Arayat', 'type': 'mall', 'distance': '1.9 km', 'icon': Icons.shopping_bag},
  ];

  @override
  void initState() {
    super.initState();
    _initializeMarkerAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocation();
    });
  }

  void _initializeMarkerAnimation() {
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: markerAnimationDurationMs),
    );
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;
    double lat2 = end.latitude * pi / 180;
    double lon2 = end.longitude * pi / 180;

    double y = sin(lon2 - lon1) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1);
    double bearing = atan2(y, x) * 180 / pi;

    return (bearing + 360) % 360;
  }

  String _getDirectionFromBearing(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return "north";
    if (bearing >= 22.5 && bearing < 67.5) return "northeast";
    if (bearing >= 67.5 && bearing < 112.5) return "east";
    if (bearing >= 112.5 && bearing < 157.5) return "southeast";
    if (bearing >= 157.5 && bearing < 202.5) return "south";
    if (bearing >= 202.5 && bearing < 247.5) return "southwest";
    if (bearing >= 247.5 && bearing < 292.5) return "west";
    return "northwest";
  }

  void _animateMarkerToNewPosition(LatLng newPosition) {
    if (_currentAnimatedPosition == null) {
      setState(() {
        _currentAnimatedPosition = newPosition;
      });
      return;
    }

    _targetPosition = newPosition;

    if (_currentAnimatedPosition != null) {
      _heading = _calculateBearing(_currentAnimatedPosition!, newPosition);
    }

    _markerAnimationController?.stop();
    _markerAnimationController?.reset();

    final startLat = _currentAnimatedPosition!.latitude;
    final startLng = _currentAnimatedPosition!.longitude;
    final endLat = newPosition.latitude;
    final endLng = newPosition.longitude;

    _markerAnimationController?.addListener(() {
      if (!mounted) return;
      final double t = _markerAnimationController!.value;
      final double interpolatedLat = startLat + (endLat - startLat) * t;
      final double interpolatedLng = startLng + (endLng - startLng) * t;

      setState(() {
        _currentAnimatedPosition = LatLng(interpolatedLat, interpolatedLng);
      });
    });

    _markerAnimationController?.forward();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = '';
    });

    try {
      bool serviceEnabled = await geolocator.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Location services are disabled';
        });
        _showLocationServicesDialog();
        return;
      }

      geolocator.LocationPermission permission = await geolocator.Geolocator.checkPermission();

      if (permission == geolocator.LocationPermission.denied) {
        permission = await geolocator.Geolocator.requestPermission();
        if (permission == geolocator.LocationPermission.denied) {
          setState(() {
            _isLoadingLocation = false;
            _locationError = 'Location permissions denied';
          });
          _showPermissionDialog();
          return;
        }
      }

      if (permission == geolocator.LocationPermission.deniedForever) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Location permissions permanently denied';
        });
        _showPermissionDialog();
        return;
      }

      geolocator.Position? position;
      int attempts = 0;
      const maxAttempts = 3;

      while (position == null && attempts < maxAttempts) {
        try {
          position = await geolocator.Geolocator.getCurrentPosition(
            desiredAccuracy: geolocator.LocationAccuracy.best,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (e) {
          attempts++;
          if (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }

      if (position != null) {
        final initialPosition = LatLng(position!.latitude, position!.longitude);
        setState(() {
          _currentPosition = initialPosition;
          _stablePosition = initialPosition;
          _currentAnimatedPosition = initialPosition;
          _previousPosition = initialPosition;
          _locationPermissionGranted = true;
          _isLoadingLocation = false;
        });

        Future.delayed(const Duration(milliseconds: 100), () {
          _mapController.move(_currentPosition!, 15);
        });

        _startLocationUpdates();
      } else {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Could not get location. Please try again.';
        });
        _showErrorDialog('Could not get your location. Please make sure you are outside or have a clear GPS signal.');
      }

    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
        _locationError = 'Error: $e';
      });
      _showErrorDialog('An error occurred while getting your location: $e');
    }
  }

  void _startLocationUpdates() {
    try {
      _locationService.startTracking(
        onPositionChanged: (position) {
          if (!mounted) return;

          double distanceMoved = 0;
          if (_stablePosition != null) {
            distanceMoved = geolocator.Geolocator.distanceBetween(
              _stablePosition!.latitude,
              _stablePosition!.longitude,
              position.latitude,
              position.longitude,
            );
          }

          if (distanceMoved > _minMovementThreshold || _stablePosition == null) {
            setState(() {
              if (_currentPosition != null) {
                _previousPosition = _currentPosition;
              }

              _stablePosition = position;
              _currentPosition = position;
              _stationaryCount = 0;

              _animateMarkerToNewPosition(position);

              if (_destination != null && !_hasArrived) {
                _checkArrival();
                _updateNavigationInstructions();
              }

              if (_isTracking) {
                _trackedRoute.add(position);

                if (_lastPositionForDistance != null) {
                  double segmentDistance = geolocator.Geolocator.distanceBetween(
                    _lastPositionForDistance!.latitude,
                    _lastPositionForDistance!.longitude,
                    position.latitude,
                    position.longitude,
                  );

                  _currentDistance += segmentDistance;

                  if (_lastTimeForSpeed != null) {
                    Duration timeDiff = DateTime.now().difference(_lastTimeForSpeed!);
                    if (timeDiff.inMilliseconds > 0) {
                      double calculatedSpeed = segmentDistance / (timeDiff.inMilliseconds / 1000);
                      _currentSpeed = calculatedSpeed;

                      if (calculatedSpeed > _maxSpeed) {
                        _maxSpeed = calculatedSpeed;
                      }
                    }
                  }
                }

                _lastPositionForDistance = position;
                _lastTimeForSpeed = DateTime.now();

                _activityService.addRoutePoint(
                  position,
                  _currentSpeed,
                  0,
                );
              }

              if (_isNavigating && !_isTracking && !_hasArrived) {
                _mapController.move(position, 15);
              }
            });
          } else {
            _stationaryCount++;
          }
        },
        onSpeedChanged: (speed) {
          if (!mounted) return;
          setState(() {
            _currentSpeed = speed;
            if (speed > _maxSpeed) {
              _maxSpeed = speed;
            }
          });
        },
      );
    } catch (e) {
      _showErrorDialog('Error starting location tracking: $e');
    }
  }

  void _updateNavigationInstructions() {
    if (_fullRoute.isEmpty || _currentPosition == null) return;

    double remainingDistance = 0;
    if (_fullRoute.isNotEmpty) {
      for (int i = 0; i < _fullRoute.length - 1; i++) {
        remainingDistance += geolocator.Geolocator.distanceBetween(
          _fullRoute[i].latitude,
          _fullRoute[i].longitude,
          _fullRoute[i + 1].latitude,
          _fullRoute[i + 1].longitude,
        );
      }
    }

    double remainingDuration = _totalDuration > 0
        ? (remainingDistance / _totalDistance) * _totalDuration
        : 0;
    DateTime eta = DateTime.now().add(Duration(seconds: remainingDuration.round()));

    setState(() {
      _formattedEta = _formatTime(eta);
      _nextInstruction = "Head ${_getDirectionFromBearing(_heading)}";
      _distanceToNextTurn = remainingDistance > 1000 ? 1000 : remainingDistance;
      _formattedDistanceToTurn = _formatDistance(_distanceToNextTurn);
    });
  }

  void _checkArrival() {
    if (_destination == null || _currentPosition == null || _hasArrived) return;

    double distanceToDestination = geolocator.Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    if (distanceToDestination <= _arrivalThreshold && !_arrivalNotified) {
      _handleArrival();
    }
  }

  void _handleArrival() {
    setState(() {
      _hasArrived = true;
      _arrivalNotified = true;
    });

    if (_isTracking) {
      _autoStopTracking();
    } else {
      _showArrivalDialog();
    }
  }

  void _autoStopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();

    await _activityService.finishActivity();

    _showArrivalDialog();

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      _showActivitySummary();
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isTracking = false;
          _isNavigating = false;
          _destination = null;
          _fullRoute = [];
          _routeInstructions = [];
          _trackedRoute = [];
          _hasArrived = false;
          _arrivalNotified = false;
          _lastPositionForDistance = null;
          _lastTimeForSpeed = null;
          _showRouteSheet = false;
          _showLandmarksSheet = false;
        });
      }
    });
  }

  void _startTracking() {
    _activityService.startNewActivity(
      '${_selectedTravelMode.capitalize()} ${DateTime.now().toString().substring(0, 16)}',
      _getActivityTypeFromString(_selectedTravelMode),
      destination: _destination,
    );

    setState(() {
      _isTracking = true;
      _trackedRoute = [];
      _currentDistance = 0;
      _currentDuration = 0;
      _currentSpeed = 0;
      _maxSpeed = 0;
      _averageSpeed = 0;
      _formattedPace = "--:--";
      _hasArrived = false;
      _arrivalNotified = false;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
    });

    _stopwatch.reset();
    _stopwatch.start();

    _timer = Timer.periodic(Duration(milliseconds: updateIntervalMs), (timer) {
      if (_isTracking && mounted) {
        setState(() {
          _currentDuration = _stopwatch.elapsedMilliseconds / 1000.0;

          if (_currentDuration > 0 && _currentDistance > 0) {
            _averageSpeed = _currentDistance / _currentDuration;

            if (_averageSpeed > 0) {
              double paceMinPerKm = 1000 / (_averageSpeed * 60);
              if (!paceMinPerKm.isInfinite && !paceMinPerKm.isNaN) {
                int minutes = paceMinPerKm.floor();
                int seconds = ((paceMinPerKm - minutes) * 60).floor();
                _formattedPace = '$minutes:${seconds.toString().padLeft(2, '0')} /km';
              }
            }
          }
        });
      }
    });
  }

  ActivityType _getActivityTypeFromString(String mode) {
    switch (mode) {
      case 'walking':
        return ActivityType.walking;
      case 'cycling':
        return ActivityType.cycling;
      default:
        return ActivityType.running;
    }
  }

  void _stopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();

    await _activityService.finishActivity();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _destination = null;
      _fullRoute = [];
      _routeInstructions = [];
      _trackedRoute = [];
      _hasArrived = false;
      _arrivalNotified = false;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
      _showRouteSheet = false;
      _showLandmarksSheet = false;
    });

    if (mounted) {
      _showActivitySummary();
    }
  }

  void _cancelTracking() {
    _stopwatch.stop();
    _timer?.cancel();
    _activityService.cancelActivity();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _destination = null;
      _fullRoute = [];
      _routeInstructions = [];
      _trackedRoute = [];
      _currentDistance = 0;
      _currentDuration = 0;
      _currentSpeed = 0;
      _maxSpeed = 0;
      _averageSpeed = 0;
      _formattedPace = "--:--";
      _hasArrived = false;
      _arrivalNotified = false;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
      _showRouteSheet = false;
      _showLandmarksSheet = false;
    });
  }

  void _showActivitySummary() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Activity Completed! 🎉'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryRow('Distance', _formatDistance(_currentDistance)),
              const Divider(),
              _buildSummaryRow('Duration', _formatDuration(_currentDuration)),
              const Divider(),
              _buildSummaryRow('Avg Speed', _formatSpeed(_averageSpeed, _selectedTravelMode)),
              const Divider(),
              _buildSummaryRow('Max Speed', _formatSpeed(_maxSpeed, _selectedTravelMode)),
              const Divider(),
              _buildSummaryRow('Avg Pace', _formattedPace),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatDuration(double seconds) {
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hours > 0) {
      return '$hours h ${minutes} min';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '${secs} sec';
    }
  }

  String _formatSpeed(double speed, String travelMode) {
    if (travelMode == 'driving' || travelMode == 'cycling') {
      double speedKmh = speed * 3.6;
      return '${speedKmh.toStringAsFixed(1)} km/h';
    } else {
      return '${speed.toStringAsFixed(1)} m/s';
    }
  }

  String _formatTime(DateTime time) {
    int hour = time.hour;
    int minute = time.minute;
    String period = hour >= 12 ? 'PM' : 'AM';

    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;

    return '$hour:${minute.toString().padLeft(2, '0')} $period';
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_isSelectingDestination && !_isTracking) {
      setState(() {
        _destination = point;
        _isSelectingDestination = false;
        _isNavigating = true;
        _hasArrived = false;
        _arrivalNotified = false;
      });
      _calculateRoute();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Destination set! ${_calculateDistanceToDestination(point)} away'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  String _calculateDistanceToDestination(LatLng destination) {
    if (_currentPosition == null) return 'Unknown';

    double distance = geolocator.Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      destination.latitude,
      destination.longitude,
    );

    return _formatDistance(distance);
  }

  Future<void> _calculateRoute() async {
    if (_currentPosition == null || _destination == null) return;

    final route = await OSRMService.getRoute(_currentPosition!, _destination!);
    final details = await OSRMService.getRouteDetails(_currentPosition!, _destination!);

    setState(() {
      if (route.isNotEmpty) {
        _fullRoute = route;
        _totalDistance = details['distance'];
        _totalDuration = details['duration'];
        _formattedTotalDistance = _formatDistance(_totalDistance);
        _formattedTotalDuration = _formatDuration(_totalDuration);

        DateTime eta = DateTime.now().add(Duration(seconds: _totalDuration.round()));
        _formattedEta = _formatTime(eta);
        _nextInstruction = "Head ${_getDirectionFromBearing(_heading)}";

        _generateMockRouteSegments();
        _generateMockNearbyLandmarks();
      }
    });

    if (route.isNotEmpty && mounted) {
      double minLat = route.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      double maxLat = route.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      double minLng = route.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      double maxLng = route.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

      _mapController.move(
        LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
        12,
      );
    }
  }

  void _generateMockRouteSegments() {
    _routeSegments = [
      {'instruction': 'Head north', 'distance': '0.3 km', 'time': '2 min', 'icon': Icons.arrow_upward},
      {'instruction': 'Turn right', 'distance': '0.5 km', 'time': '3 min', 'icon': Icons.turn_right},
      {'instruction': 'Continue straight', 'distance': '1.2 km', 'time': '5 min', 'icon': Icons.arrow_forward},
      {'instruction': 'Turn left', 'distance': '0.4 km', 'time': '2 min', 'icon': Icons.turn_left},
      {'instruction': 'Arrive at destination', 'distance': '0.1 km', 'time': '1 min', 'icon': Icons.flag},
    ];
  }

  void _generateMockNearbyLandmarks() {
    _nearbyLandmarks = _mockLandmarks.take(8).toList();
  }

  void _centerOnCurrentLocation() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 16);
    }
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_emotions,
                  color: Colors.green,
                  size: 50,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You Have Arrived! 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You have reached your destination.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _destination != null
                            ? 'Lat: ${_destination!.latitude.toStringAsFixed(4)}, Lng: ${_destination!.longitude.toStringAsFixed(4)}'
                            : 'Destination reached',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showRouteBottomSheet() {
    setState(() {
      _showRouteSheet = true;
      _showLandmarksSheet = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Route Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _showRouteSheet = false;
                      });
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _routeSegments.length,
                itemBuilder: (context, index) {
                  final segment = _routeSegments[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _travelModeColors[_selectedTravelMode]?.withValues(alpha: 0.1) ?? Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            segment['icon'],
                            color: _travelModeColors[_selectedTravelMode] ?? Colors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                segment['instruction'],
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${segment['distance']} • ${segment['time']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      setState(() {
        _showRouteSheet = false;
      });
    });
  }

  void _showLandmarksBottomSheet() {
    setState(() {
      _showLandmarksSheet = true;
      _showRouteSheet = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Along the Way',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _showLandmarksSheet = false;
                      });
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _nearbyLandmarks.length,
                itemBuilder: (context, index) {
                  final landmark = _nearbyLandmarks[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            landmark['icon'],
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                landmark['name'],
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                landmark['distance'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            landmark['type'],
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      setState(() {
        _showLandmarksSheet = false;
      });
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Retry'),
              onPressed: () {
                Navigator.of(context).pop();
                _initializeLocation();
              },
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
              'Strava needs access to your location to track your activities. Please enable location permissions in settings.'
          ),
          actions: [
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                geolocator.Geolocator.openLocationSettings();
              },
            ),
            TextButton(
              child: const Text('Retry'),
              onPressed: () {
                Navigator.of(context).pop();
                _initializeLocation();
              },
            ),
          ],
        );
      },
    );
  }

  void _showLocationServicesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text(
              'Please enable location services in your device settings to use Strava.'
          ),
          actions: [
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                geolocator.Geolocator.openLocationSettings();
              },
            ),
            TextButton(
              child: const Text('Retry'),
              onPressed: () {
                Navigator.of(context).pop();
                _initializeLocation();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Color currentColor = _travelModeColors[_selectedTravelMode] ?? Colors.blue;

    if (_isLoadingLocation) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Getting your location...',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              if (_locationError.isNotEmpty)
                Text(
                  _locationError,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeLocation,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_locationPermissionGranted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Activity'),
          backgroundColor: Colors.blue,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.location_off,
                  size: 80,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Location Permission Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Strava needs access to your location to track your activities.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    geolocator.Geolocator.openLocationSettings();
                  },
                  child: const Text('Open Settings'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _initializeLocation,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Activity'),
        backgroundColor: currentColor.withValues(alpha: 0.9),
        foregroundColor: Colors.white,
        actions: [
          if (!_isTracking && !_isNavigating)
            PopupMenuButton<String>(
              icon: const Icon(Icons.directions),
              onSelected: (value) {
                setState(() {
                  _selectedTravelMode = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'driving', child: Row(children: [Icon(Icons.directions_car, color: Colors.blue), SizedBox(width: 8), Text('Driving')])),
                const PopupMenuItem(value: 'walking', child: Row(children: [Icon(Icons.directions_walk, color: Colors.green), SizedBox(width: 8), Text('Walking')])),
                const PopupMenuItem(value: 'cycling', child: Row(children: [Icon(Icons.directions_bike, color: Colors.orange), SizedBox(width: 8), Text('Cycling')])),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(14.5995, 120.9842),
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.strava',
                tileProvider: CancellableNetworkTileProvider(),
              ),

              // Route to destination
              if (_fullRoute.isNotEmpty && !_hasArrived && _destination != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _fullRoute,
                      color: currentColor.withValues(alpha: 0.8),
                      strokeWidth: 5,
                    ),
                  ],
                ),

              // Tracked route
              if (_trackedRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackedRoute,
                      color: currentColor.withValues(alpha: 0.4),
                      strokeWidth: 4,
                    ),
                  ],
                ),

              if (_destination != null && _isNavigating)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _destination!,
                      color: Colors.green.withValues(alpha: 0.2),
                      borderColor: Colors.green,
                      borderStrokeWidth: 2,
                      radius: _arrivalThreshold,
                    ),
                  ],
                ),

              // Google Maps Style Current Position Marker
              MarkerLayer(
                markers: [
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer ring pulse animation
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeInOut,
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: currentColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Inner blue dot
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: currentColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          // Direction indicator (like Google Maps)
                          if (_currentSpeed > 0.5)
                            Positioned(
                              top: 0,
                              child: Transform.rotate(
                                angle: _heading * pi / 180,
                                child: Container(
                                  width: 4,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Google Maps Style Destination Marker
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 40,
                      height: 40,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (!_hasArrived)
                            const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 40,
                            ),
                          if (_hasArrived)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Navigation Header (Google Maps Style)
          if (_isNavigating && _destination != null && !_hasArrived)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formattedEta,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_formattedTotalDistance • $_formattedTotalDuration',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: currentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(_travelModeIcons[_selectedTravelMode], size: 16, color: currentColor),
                              const SizedBox(width: 4),
                              Text(
                                _selectedTravelMode.capitalize(),
                                style: TextStyle(
                                  color: currentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: currentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.arrow_upward,
                              color: currentColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nextInstruction,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Then • ${_routeSegments.isNotEmpty ? _routeSegments[0]['instruction'] : ''}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _formattedDistanceToTurn,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Clickable Buttons for Route and Landmarks
          if (_isNavigating && !_hasArrived)
            Positioned(
              top: _isNavigating ? 200 : 16,
              left: 16,
              child: Row(
                children: [
                  _buildActionButton(
                    icon: Icons.route,
                    label: 'Route',
                    color: currentColor,
                    onPressed: _showRouteBottomSheet,
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.place,
                    label: 'Along the way',
                    color: Colors.green,
                    onPressed: _showLandmarksBottomSheet,
                  ),
                ],
              ),
            ),

          // Live Tracking Stats Card
          if (_isTracking)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          'Distance',
                          _formatDistance(_currentDistance),
                          Icons.straighten,
                          currentColor,
                        ),
                        _buildStatItem(
                          'Duration',
                          _formatDuration(_currentDuration),
                          Icons.timer,
                          currentColor,
                        ),
                        _buildStatItem(
                          'Speed',
                          _formatSpeed(_currentSpeed, _selectedTravelMode),
                          Icons.speed,
                          currentColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          'Avg Pace',
                          _formattedPace,
                          Icons.timer_outlined,
                          currentColor,
                        ),
                        _buildStatItem(
                          'Max Speed',
                          _formatSpeed(_maxSpeed, _selectedTravelMode),
                          Icons.flash_on,
                          currentColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Map Controls
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              children: [
                _buildControlButton(Icons.add, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1)),
                const SizedBox(height: 8),
                _buildControlButton(Icons.remove, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1)),
                const SizedBox(height: 8),
                _buildControlButton(Icons.my_location, _centerOnCurrentLocation),
                if (!_isTracking && !_isNavigating) ...[
                  const SizedBox(height: 8),
                  _buildControlButton(Icons.place, () {
                    setState(() {
                      _isSelectingDestination = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tap on the map to set destination'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }, color: Colors.red),
                ],
                if (_isNavigating && !_isTracking) ...[
                  const SizedBox(height: 8),
                  _buildControlButton(Icons.close, () {
                    setState(() {
                      _destination = null;
                      _fullRoute = [];
                      _routeInstructions = [];
                      _nearbyLandmarks = [];
                      _routeSegments = [];
                      _isNavigating = false;
                      _hasArrived = false;
                      _arrivalNotified = false;
                    });
                  }, color: Colors.red),
                ],
              ],
            ),
          ),

          // Start/Stop Buttons
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isTracking)
                      ElevatedButton.icon(
                        onPressed: _currentPosition != null ? _startTracking : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_isNavigating ? 'Start' : 'Start'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    if (_isTracking) ...[
                      ElevatedButton.icon(
                        onPressed: _stopTracking,
                        icon: const Icon(Icons.stop),
                        label: const Text('Finish'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _cancelTracking,
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getLandmarkIcon(String type) {
    switch (type) {
      case 'mall': return Icons.shopping_bag;
      case 'shop': return Icons.shop;
      case 'cafe': return Icons.local_cafe;
      case 'restaurant': return Icons.restaurant;
      case 'market': return Icons.store;
      case 'landmark': return Icons.location_city;
      case 'street': return Icons.add_road;
      default: return Icons.place;
    }
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {Color color = Colors.blue}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() => "${this[0].toUpperCase()}${substring(1)}";
}