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
  List<LatLng> _remainingRoute = [];
  List<Map<String, dynamic>> _routeInstructions = [];
  List<Map<String, dynamic>> _routeSegments = [];
  List<String> _routePlaces = [];

  // Navigation state
  bool _isTracking = false;
  bool _isSelectingDestination = false;
  bool _isNavigating = false;
  String _selectedTravelMode = 'driving';
  bool _locationPermissionGranted = false;
  bool _isLoadingLocation = true;
  String _locationError = '';

  // Turn notification
  bool _showTurnNotificationPopup = false;
  String _currentTurnInstruction = "";
  String _currentTurnDistance = "";
  IconData _currentTurnIcon = Icons.arrow_forward;
  Timer? _turnNotificationTimer;

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

  // Live tracking metrics
  double _currentSpeed = 0;
  double _currentDistance = 0;
  double _currentDuration = 0;
  double _maxSpeed = 0;
  double _averageSpeed = 0;

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

  // Turn detection
  int _currentRouteIndex = 0;
  bool _turnNotifiedForCurrentSegment = false;

  // Flag to track if user has started moving towards destination
  bool _hasStartedMovingToDestination = false;

  static const int updateIntervalMs = 100;
  static const int markerAnimationDurationMs = 500;
  static const int turnNotificationDurationMs = 4000;

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
            locationSettings: const geolocator.LocationSettings(
              accuracy: geolocator.LocationAccuracy.best,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (e) {
          attempts++;
          if (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }

      if (position != null) {
        final initialPosition = LatLng(position.latitude, position.longitude);
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
                _updateRemainingRoute(position);
                _checkForTurn(position);

                // Check if user has started moving towards destination
                if (!_hasStartedMovingToDestination && _remainingRoute.isNotEmpty) {
                  _hasStartedMovingToDestination = true;
                }
              }

              if (_isTracking) {
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

  void _checkForTurn(LatLng currentPosition) {
    if (_remainingRoute.length < 3 || _turnNotifiedForCurrentSegment) return;

    // Get current direction and next direction
    LatLng currentPoint = _remainingRoute[0];
    LatLng nextPoint = _remainingRoute[1];
    LatLng futurePoint = _remainingRoute[2];

    double currentBearing = _calculateBearing(currentPoint, nextPoint);
    double nextBearing = _calculateBearing(nextPoint, futurePoint);

    // Calculate turn angle
    double turnAngle = nextBearing - currentBearing;
    if (turnAngle > 180) turnAngle -= 360;
    if (turnAngle < -180) turnAngle += 360;

    // Calculate distance to turn
    double distanceToTurn = geolocator.Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

    // Show turn notification when approaching a turn (within 50 meters)
    if (distanceToTurn < 50 && turnAngle.abs() > 20 && !_turnNotifiedForCurrentSegment) {
      String instruction = _getTurnInstruction(turnAngle);
      IconData icon = _getTurnIcon(turnAngle);
      String distanceStr = _formatDistance(distanceToTurn);

      _showTurnNotificationPopupMethod(instruction, distanceStr, icon);
      _turnNotifiedForCurrentSegment = true;
    }
  }

  String _getTurnInstruction(double turnAngle) {
    if (turnAngle.abs() < 20) return "Continue straight";
    if (turnAngle > 20 && turnAngle < 60) return "Turn slight right";
    if (turnAngle >= 60 && turnAngle < 150) return "Turn right";
    if (turnAngle >= 150) return "Make a U-turn";
    if (turnAngle < -20 && turnAngle > -60) return "Turn slight left";
    if (turnAngle <= -60 && turnAngle > -150) return "Turn left";
    return "Continue";
  }

  IconData _getTurnIcon(double turnAngle) {
    if (turnAngle.abs() < 20) return Icons.arrow_upward;
    if (turnAngle > 20 && turnAngle < 60) return Icons.turn_right;
    if (turnAngle >= 60 && turnAngle < 150) return Icons.turn_right;
    if (turnAngle >= 150) return Icons.autorenew;
    if (turnAngle < -20 && turnAngle > -60) return Icons.turn_left;
    if (turnAngle <= -60 && turnAngle > -150) return Icons.turn_left;
    return Icons.arrow_upward;
  }

  void _showTurnNotificationPopupMethod(String instruction, String distance, IconData icon) {
    _turnNotificationTimer?.cancel();

    setState(() {
      _showTurnNotificationPopup = true;
      _currentTurnInstruction = instruction;
      _currentTurnDistance = distance;
      _currentTurnIcon = icon;
    });

    _turnNotificationTimer = Timer(Duration(milliseconds: turnNotificationDurationMs), () {
      if (mounted) {
        setState(() {
          _showTurnNotificationPopup = false;
        });
      }
    });
  }

  void _updateRemainingRoute(LatLng currentPosition) {
    if (_remainingRoute.isEmpty || _destination == null) return;

    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < _remainingRoute.length; i++) {
      double distance = geolocator.Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        _remainingRoute[i].latitude,
        _remainingRoute[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    if (minDistance < 30) {
      if (closestIndex + 2 < _remainingRoute.length) {
        _remainingRoute = _remainingRoute.sublist(closestIndex + 2);
        _currentRouteIndex++;
        _turnNotifiedForCurrentSegment = false;
      } else {
        _remainingRoute = [];
      }
      setState(() {});
    }
  }

  void _updateNavigationInstructions() {
    if (_remainingRoute.isEmpty || _currentPosition == null) return;

    double remainingDistance = 0;
    if (_remainingRoute.isNotEmpty) {
      for (int i = 0; i < _remainingRoute.length - 1; i++) {
        remainingDistance += geolocator.Geolocator.distanceBetween(
          _remainingRoute[i].latitude,
          _remainingRoute[i].longitude,
          _remainingRoute[i + 1].latitude,
          _remainingRoute[i + 1].longitude,
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

    // Check if user has reached the destination
    if (distanceToDestination <= _arrivalThreshold && !_arrivalNotified) {
      _handleArrival();
    }
  }

  void _handleArrival() {
    setState(() {
      _hasArrived = true;
      _arrivalNotified = true;
      _remainingRoute = [];
      _showTurnNotificationPopup = false;
    });

    // Show arrival dialog
    _showArrivalDialog();

    // If currently tracking, finish the activity
    if (_isTracking) {
      _autoStopTracking();
    }
  }

  void _autoStopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();

    await _activityService.finishActivity();

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      _showActivitySummary();
    }

    // Reset navigation state after summary
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isTracking = false;
          _isNavigating = false;
          _destination = null;
          _remainingRoute = [];
          _hasArrived = false;
          _arrivalNotified = false;
          _lastPositionForDistance = null;
          _lastTimeForSpeed = null;
          _showTurnNotificationPopup = false;
          _currentRouteIndex = 0;
          _turnNotifiedForCurrentSegment = false;
          _hasStartedMovingToDestination = false;
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
      _currentDistance = 0;
      _currentDuration = 0;
      _currentSpeed = 0;
      _maxSpeed = 0;
      _averageSpeed = 0;
      _hasArrived = false;
      _arrivalNotified = false;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
      _currentRouteIndex = 0;
      _turnNotifiedForCurrentSegment = false;
      _hasStartedMovingToDestination = true; // User has started moving
    });

    _stopwatch.reset();
    _stopwatch.start();

    _timer = Timer.periodic(Duration(milliseconds: updateIntervalMs), (timer) {
      if (_isTracking && mounted) {
        setState(() {
          _currentDuration = _stopwatch.elapsedMilliseconds / 1000.0;

          if (_currentDuration > 0 && _currentDistance > 0) {
            _averageSpeed = _currentDistance / _currentDuration;
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

  // When destination is set but not tracking, only show Cancel button
  void _cancelDestination() {
    setState(() {
      _destination = null;
      _remainingRoute = [];
      _routeSegments = [];
      _routePlaces = [];
      _isNavigating = false;
      _hasArrived = false;
      _arrivalNotified = false;
      _showTurnNotificationPopup = false;
      _hasStartedMovingToDestination = false;
    });
  }

  // Only used when tracking without destination
  void _stopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();

    await _activityService.finishActivity();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _currentDistance = 0;
      _currentDuration = 0;
      _currentSpeed = 0;
      _maxSpeed = 0;
      _averageSpeed = 0;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
      _showTurnNotificationPopup = false;
      _currentRouteIndex = 0;
      _turnNotifiedForCurrentSegment = false;
      _hasStartedMovingToDestination = false;
    });

    if (mounted) {
      _showActivitySummary();
    }
  }

  // Only used when tracking without destination
  void _cancelTracking() {
    _stopwatch.stop();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();
    _activityService.cancelActivity();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _currentDistance = 0;
      _currentDuration = 0;
      _currentSpeed = 0;
      _maxSpeed = 0;
      _averageSpeed = 0;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
      _showTurnNotificationPopup = false;
      _currentRouteIndex = 0;
      _turnNotifiedForCurrentSegment = false;
      _hasStartedMovingToDestination = false;
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
      return '${hours}h ${minutes}min';
    } else if (minutes > 0) {
      return '${minutes}min';
    } else {
      return '${secs}sec';
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
        _currentRouteIndex = 0;
        _turnNotifiedForCurrentSegment = false;
        _hasStartedMovingToDestination = false;
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

    // Generate mock place names along the route (for bottom sheet)
    _generateMockRoutePlaces();

    setState(() {
      if (route.isNotEmpty) {
        _remainingRoute = route;
        _totalDistance = details['distance'];
        _totalDuration = details['duration'];
        _formattedTotalDistance = _formatDistance(_totalDistance);
        _formattedTotalDuration = _formatDuration(_totalDuration);

        DateTime eta = DateTime.now().add(Duration(seconds: _totalDuration.round()));
        _formattedEta = _formatTime(eta);
        _nextInstruction = "Head ${_getDirectionFromBearing(_heading)}";

        _generateMockRouteSegments();
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

  void _generateMockRoutePlaces() {
    _routePlaces = [
      'Camias', 'Baliti', 'Pandacaqui', 'Telapayong', 'Arenas',
      'San Roque', 'Bitas', 'Culubasa', 'Sucaban', 'Tabang',
      'Anao', 'San Pablo', 'San Antonio', 'San Francisco', 'San Juanito',
      'San Nicolas', 'San Pedro', 'San Agustin', 'San Luis', 'Dolores',
      'San Isidro', 'San Carlos', 'San Mateo', 'Santa Lucia', 'Santo Cristo'
    ];
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
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: const TabBar(
                        tabs: [
                          Tab(text: 'Directions'),
                          Tab(text: 'Places'),
                        ],
                        labelColor: Colors.blue,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Colors.blue,
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Directions Tab
                          ListView.builder(
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
                                  ],
                                ),
                              );
                            },
                          ),

                          // Places Tab
                          ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _routePlaces.length,
                            itemBuilder: (context, index) {
                              final place = _routePlaces[index];
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
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: index < 3 ? Colors.green : Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        place,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: index < 3 ? FontWeight.bold : FontWeight.normal,
                                          color: index < 3 ? Colors.black : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                    if (index == 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Next',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

              // Only show remaining route (disappears as you pass)
              if (_remainingRoute.isNotEmpty && !_hasArrived && _destination != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _remainingRoute,
                      color: currentColor.withValues(alpha: 0.8),
                      strokeWidth: 5,
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

          // SMALLER Live Tracking Stats Card (only shown when tracking)
          if (_isTracking)
            Positioned(
              top: _isNavigating ? 180 : 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Distance
                    _buildCompactStat(
                      value: _formatDistance(_currentDistance),
                      icon: Icons.straighten,
                      color: currentColor,
                    ),

                    // Vertical divider
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.shade300,
                    ),

                    // Duration
                    _buildCompactStat(
                      value: _formatDuration(_currentDuration),
                      icon: Icons.timer,
                      color: currentColor,
                    ),

                    // Vertical divider
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.shade300,
                    ),

                    // Speed
                    _buildCompactStat(
                      value: _formatSpeed(_currentSpeed, _selectedTravelMode),
                      icon: Icons.speed,
                      color: currentColor,
                    ),

                    // Vertical divider
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.shade300,
                    ),

                    // Max Speed
                    _buildCompactStat(
                      value: _formatSpeed(_maxSpeed, _selectedTravelMode),
                      icon: Icons.flash_on,
                      color: currentColor,
                    ),
                  ],
                ),
              ),
            ),

          // Turn Notification Popup
          if (_showTurnNotificationPopup)
            Positioned(
              top: _isNavigating ? 250 : 80,
              left: 20,
              right: 20,
              child: TweenAnimationBuilder(
                duration: const Duration(milliseconds: 300),
                tween: Tween<double>(begin: 0, end: 1),
                curve: Curves.easeOutBack,
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: currentColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(
                          color: currentColor,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: currentColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _currentTurnIcon,
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
                                  _currentTurnInstruction,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'in $_currentTurnDistance',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Route Button - only shown when destination is set but not tracking
          if (_isNavigating && !_isTracking && !_hasArrived)
            Positioned(
              top: 240,
              left: 16,
              child: _buildActionButton(
                icon: Icons.route,
                label: 'Route',
                color: currentColor,
                onPressed: _showRouteBottomSheet,
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
              ],
            ),
          ),

          // Bottom Buttons - Different based on state
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Case 1: Destination set but not tracking - ONLY Cancel button
                    if (_isNavigating && !_isTracking && !_hasArrived)
                      OutlinedButton(
                        onPressed: _cancelDestination,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size(100, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),

                    // Case 2: Tracking without destination - Show Finish and Cancel
                    if (_isTracking && !_isNavigating) ...[
                      ElevatedButton(
                        onPressed: _stopTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(80, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Finish'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _cancelTracking,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size(80, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],

                    // Case 3: Tracking with destination - Only show Cancel button (arrival auto-finishes)
                    if (_isTracking && _isNavigating)
                      OutlinedButton(
                        onPressed: _cancelTracking,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size(100, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),

                    // Case 4: No destination and not tracking - Show Start button
                    if (!_isTracking && !_isNavigating)
                      ElevatedButton(
                        onPressed: _currentPosition != null ? _startTracking : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(100, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Start'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for compact stats
  Widget _buildCompactStat({
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {Color color = Colors.blue}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() => "${this[0].toUpperCase()}${substring(1)}";
}