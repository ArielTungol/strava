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
  // Updated to 5 meters as requested for better GPS reliability
  final double _arrivalThreshold = 5.0;
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

  @override
  void dispose() {
    _markerAnimationController?.dispose();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();
    _locationService.stopTracking();
    super.dispose();
  }

  void _initializeMarkerAnimation() {
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: markerAnimationDurationMs),
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
        _showErrorDialog('Could not get your location.');
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

          // Constant check for arrival
          if (_destination != null && !_hasArrived && mounted) {
            _checkArrival();
          }

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
                _updateNavigationInstructions();
                _updateRemainingRoute(position);
                _checkForTurn(position);
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

  void _checkArrival() {
    if (_destination == null || _currentPosition == null || _hasArrived) return;

    double distanceToDestination = geolocator.Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    // Using the updated 5 meter threshold
    if (distanceToDestination <= _arrivalThreshold && !_arrivalNotified) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleArrival();
        }
      });
    }
  }

  void _checkForTurn(LatLng currentPosition) {
    if (_remainingRoute.length < 3 || _turnNotifiedForCurrentSegment) return;

    LatLng currentPoint = _remainingRoute[0];
    LatLng nextPoint = _remainingRoute[1];
    LatLng futurePoint = _remainingRoute[2];

    double currentBearing = _calculateBearing(currentPoint, nextPoint);
    double nextBearing = _calculateBearing(nextPoint, futurePoint);

    double turnAngle = nextBearing - currentBearing;
    if (turnAngle > 180) turnAngle -= 360;
    if (turnAngle < -180) turnAngle += 360;

    double distanceToTurn = geolocator.Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

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

    _turnNotificationTimer = Timer(const Duration(milliseconds: turnNotificationDurationMs), () {
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

  void _handleArrival() {
    setState(() {
      _hasArrived = true;
      _arrivalNotified = true;
      _remainingRoute = [];
      _showTurnNotificationPopup = false;
    });

    // Auto-save logic
    if (_isTracking) {
      _autoStopTracking();
    } else {
      _showArrivalDialog();
    }
  }

  void _autoStopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();

    // Saves the activity to history
    await _activityService.finishActivity();

    // Show arrival summary
    await _showArrivalDialog();

    if (mounted) {
      setState(() {
        _isTracking = false;
        _isNavigating = false;
        _remainingRoute = [];
        _hasArrived = false;
        _arrivalNotified = false;
        _lastPositionForDistance = null;
        _lastTimeForSpeed = null;
        _showTurnNotificationPopup = false;
        _currentRouteIndex = 0;
        _turnNotifiedForCurrentSegment = false;
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _destination = null;
          });
        }
      });
    }
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
    });

    _stopwatch.reset();
    _stopwatch.start();

    _timer = Timer.periodic(const Duration(milliseconds: updateIntervalMs), (timer) {
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

  void _stopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();

    await _activityService.finishActivity();

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
    });

    if (mounted) {
      _showActivitySummary();
    }
  }

  void _cancelTracking() {
    _stopwatch.stop();
    _timer?.cancel();
    _turnNotificationTimer?.cancel();
    _activityService.cancelActivity();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _destination = null;
      _remainingRoute = [];
      _currentDistance = 0;
      _currentDuration = 0;
      _currentSpeed = 0;
      _maxSpeed = 0;
      _averageSpeed = 0;
      _hasArrived = false;
      _arrivalNotified = false;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
      _showTurnNotificationPopup = false;
      _currentRouteIndex = 0;
      _turnNotifiedForCurrentSegment = false;
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
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
      });
      _calculateRoute();
    }
  }

  Future<void> _calculateRoute() async {
    if (_currentPosition == null || _destination == null) return;

    final route = await OSRMService.getRoute(_currentPosition!, _destination!);
    final details = await OSRMService.getRouteDetails(_currentPosition!, _destination!);

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
      _mapController.move(route[0], 15);
    }
  }

  void _generateMockRoutePlaces() {
    _routePlaces = ['Location A', 'Location B', 'Location C'];
  }

  void _generateMockRouteSegments() {
    _routeSegments = [
      {'instruction': 'Head north', 'distance': '0.3 km', 'time': '2 min', 'icon': Icons.arrow_upward},
      {'instruction': 'Arrive at destination', 'distance': '0.1 km', 'time': '1 min', 'icon': Icons.flag},
    ];
  }

  void _centerOnCurrentLocation() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 16);
    }
  }

  Future<void> _showArrivalDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.emoji_emotions, color: Colors.green, size: 50),
              SizedBox(height: 16),
              Text('You Have Arrived! 🎉', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You have reached your destination.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              if (_isTracking || _arrivalNotified) ...[
                _buildSummaryRow('Distance', _formatDistance(_currentDistance)),
                _buildSummaryRow('Duration', _formatDuration(_currentDuration)),
              ]
            ],
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Route Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Expanded(child: Center(child: Text("Route Directions List"))),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text('Enable location to track activities.'),
        actions: [TextButton(onPressed: () => geolocator.Geolocator.openLocationSettings(), child: const Text('Settings'))],
      ),
    );
  }

  void _showLocationServicesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Services Disabled'),
        content: const Text('Enable location services to proceed.'),
        actions: [TextButton(onPressed: () => geolocator.Geolocator.openLocationSettings(), child: const Text('Enable'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color currentColor = _travelModeColors[_selectedTravelMode] ?? Colors.blue;

    if (_isLoadingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Activity'),
        backgroundColor: currentColor,
        actions: [
          if (!_isTracking && !_isNavigating)
            IconButton(icon: const Icon(Icons.directions), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(14.5995, 120.9842),
              initialZoom: 15,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.strava',
                tileProvider: CancellableNetworkTileProvider(),
              ),
              if (_remainingRoute.isNotEmpty && !_hasArrived)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _remainingRoute, color: currentColor, strokeWidth: 5),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      ),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_pin, color: _hasArrived ? Colors.green : Colors.red, size: 40),
                    ),
                ],
              ),
            ],
          ),

          // Nav Header
          if (_isNavigating && _destination != null && !_hasArrived)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                color: Colors.white,
                child: Text("ETA: $_formattedEta - $_formattedTotalDistance", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),

          // Stats
          if (_isTracking)
            Positioned(
              top: 100, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCompactStat(value: _formatDistance(_currentDistance), icon: Icons.straighten, color: currentColor),
                    _buildCompactStat(value: _formatDuration(_currentDuration), icon: Icons.timer, color: currentColor),
                  ],
                ),
              ),
            ),

          // Map Controls
          Positioned(
            bottom: 100, right: 16,
            child: Column(
              children: [
                _buildControlButton(Icons.my_location, _centerOnCurrentLocation),
                const SizedBox(height: 8),
                _buildControlButton(Icons.place, () => setState(() => _isSelectingDestination = true), color: Colors.red),
              ],
            ),
          ),

          // Controls
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isTracking)
                    ElevatedButton(onPressed: _startTracking, child: const Text('Start')),
                  if (_isTracking) ...[
                    ElevatedButton(onPressed: _stopTracking, child: const Text('Finish')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _cancelTracking, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Cancel')),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat({required String value, required IconData icon, required Color color}) {
    return Column(children: [Icon(icon, color: color, size: 16), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]);
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {Color color = Colors.blue}) {
    return Container(
      color: Colors.white,
      child: IconButton(icon: Icon(icon, color: color), onPressed: onPressed),
    );
  }
}

extension StringExtension on String {
  String capitalize() => "${this[0].toUpperCase()}${substring(1)}";
}