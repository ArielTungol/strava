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

  LatLng? _currentPosition;
  LatLng? _previousPosition;
  double _heading = 0.0;
  LatLng? _destination;
  List<LatLng> _fullRoute = []; // Complete route from start to destination
  List<LatLng> _remainingRoute = []; // Route that hasn't been traveled yet (disappears as you pass)
  List<LatLng> _trackedRoute = []; // Route that has been traveled

  bool _isTracking = false;
  bool _isSelectingDestination = false;
  bool _isNavigating = false;
  String _selectedActivity = 'running';
  bool _locationPermissionGranted = false;
  bool _isLoadingLocation = true;
  String _locationError = '';

  // Arrival detection
  bool _hasArrived = false;
  double _arrivalThreshold = 20.0;
  bool _arrivalNotified = false;

  // Live tracking metrics
  double _currentSpeed = 0;
  double _currentDistance = 0;
  double _currentDuration = 0;
  double _maxSpeed = 0;
  double _averageSpeed = 0;
  String _formattedPace = "--:--";

  // For tracking movement
  LatLng? _lastPositionForDistance;
  DateTime? _lastTimeForSpeed;

  Timer? _timer;
  Stopwatch _stopwatch = Stopwatch();

  // Animation for smooth marker movement
  AnimationController? _markerAnimationController;
  LatLng? _targetPosition;
  LatLng? _currentAnimatedPosition;

  static const int UPDATE_INTERVAL_MS = 100;
  static const int MARKER_ANIMATION_DURATION_MS = 500;

  final Map<ActivityType, IconData> _activityIcons = {
    ActivityType.running: Icons.directions_run,
    ActivityType.walking: Icons.directions_walk,
    ActivityType.cycling: Icons.directions_bike,
  };

  final Map<ActivityType, Color> _activityColors = {
    ActivityType.running: Colors.orange,
    ActivityType.walking: Colors.green,
    ActivityType.cycling: Colors.blue,
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
      duration: Duration(milliseconds: MARKER_ANIMATION_DURATION_MS),
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

      print('📍 Attempting to get current location...');

      geolocator.Position? position;
      int attempts = 0;
      const maxAttempts = 3;

      while (position == null && attempts < maxAttempts) {
        try {
          position = await geolocator.Geolocator.getCurrentPosition(
            desiredAccuracy: geolocator.LocationAccuracy.best,
            timeLimit: const Duration(seconds: 5),
          );
          print('✅ Got location on attempt ${attempts + 1}');
        } catch (e) {
          attempts++;
          print('❌ Attempt $attempts failed: $e');
          if (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }

      if (position != null) {
        final initialPosition = LatLng(position!.latitude, position!.longitude);
        setState(() {
          _currentPosition = initialPosition;
          _currentAnimatedPosition = initialPosition;
          _previousPosition = initialPosition;
          _locationPermissionGranted = true;
          _isLoadingLocation = false;
        });

        print('📍 Current position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

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
      print('❌ Error in location initialization: $e');
      setState(() {
        _isLoadingLocation = false;
        _locationError = 'Error: $e';
      });
      _showErrorDialog('An error occurred while getting your location: $e');
    }
  }

  void _startLocationUpdates() {
    print('📍 Starting location updates...');

    try {
      _locationService.startTracking(
        onPositionChanged: (position) {
          if (!mounted) return;

          print('📍 Position update received: $position');

          setState(() {
            if (_currentPosition != null) {
              _previousPosition = _currentPosition;
            }

            LatLng oldPosition = _currentPosition ?? position;
            _currentPosition = position;

            // Check if arrived at destination
            if (_destination != null && !_hasArrived) {
              _checkArrival();
            }

            if (_isTracking) {
              _trackedRoute.add(position);

              // Update remaining route - remove traveled portion
              if (_fullRoute.isNotEmpty) {
                _updateRemainingRoute(position);
              }

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

            _animateMarkerToNewPosition(position);

            if (_isNavigating && !_isTracking && !_hasArrived) {
              _mapController.move(position, 15);
            }
          });
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
      print('❌ Error starting location updates: $e');
      _showErrorDialog('Error starting location tracking: $e');
    }
  }

  void _updateRemainingRoute(LatLng currentPosition) {
    if (_fullRoute.isEmpty || _destination == null) return;

    // Find the closest point on the route to current position
    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < _fullRoute.length; i++) {
      double distance = geolocator.Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        _fullRoute[i].latitude,
        _fullRoute[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // If we're close to the route, update remaining route
    // This removes all points up to the closest index, making the polyline disappear as you pass
    if (minDistance < 30) { // Within 30 meters of the route
      // Add a small offset to ensure we don't cut off too early
      int offsetIndex = closestIndex + 2;
      if (offsetIndex >= _fullRoute.length) {
        offsetIndex = _fullRoute.length - 1;
      }

      // Only update if the new remaining route is shorter
      if (offsetIndex < _remainingRoute.length) {
        _remainingRoute = _fullRoute.sublist(offsetIndex);
        print('📍 Route updated: ${_remainingRoute.length} points remaining');
      }
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

    print('📍 Distance to destination: ${distanceToDestination.toStringAsFixed(1)}m');

    if (distanceToDestination <= _arrivalThreshold && !_arrivalNotified) {
      _handleArrival();
    }
  }

  void _handleArrival() {
    setState(() {
      _hasArrived = true;
      _arrivalNotified = true;
      _remainingRoute = []; // Clear remaining route when arrived
    });

    if (_isTracking) {
      _autoStopTracking();
    } else {
      _showArrivalDialog();
    }
  }

  void _autoStopTracking() async {
    print('📍 AUTO-STOP: Reached destination, finishing activity...');

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
          _remainingRoute = [];
          _hasArrived = false;
          _arrivalNotified = false;
          _lastPositionForDistance = null;
          _lastTimeForSpeed = null;
        });
      }
    });
  }

  void _startTracking() {
    ActivityType type;
    switch (_selectedActivity) {
      case 'running':
        type = ActivityType.running;
        break;
      case 'walking':
        type = ActivityType.walking;
        break;
      case 'cycling':
        type = ActivityType.cycling;
        break;
      default:
        type = ActivityType.running;
    }

    _activityService.startNewActivity(
      '${_selectedActivity.capitalize()} ${DateTime.now().toString().substring(0, 16)}',
      type,
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

      // Initialize remaining route as full route when starting
      if (_fullRoute.isNotEmpty) {
        _remainingRoute = List.from(_fullRoute);
      }
    });

    _stopwatch.reset();
    _stopwatch.start();

    _timer = Timer.periodic(const Duration(milliseconds: UPDATE_INTERVAL_MS), (timer) {
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

  void _stopTracking() async {
    _stopwatch.stop();
    _timer?.cancel();

    await _activityService.finishActivity();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _destination = null;
      _fullRoute = [];
      _remainingRoute = [];
      _hasArrived = false;
      _arrivalNotified = false;
      _lastPositionForDistance = null;
      _lastTimeForSpeed = null;
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
      _remainingRoute = [];
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
              _buildSummaryRow('Avg Speed', _formatSpeed(_averageSpeed, _selectedActivity)),
              const Divider(),
              _buildSummaryRow('Max Speed', _formatSpeed(_maxSpeed, _selectedActivity)),
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
    if (meters < 1000) return '${meters.toStringAsFixed(1)}m';
    return '${(meters / 1000).toStringAsFixed(2)}km';
  }

  String _formatDuration(double seconds) {
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  String _formatSpeed(double speed, String activityType) {
    if (activityType == 'cycling') {
      double speedKmh = speed * 3.6;
      return '${speedKmh.toStringAsFixed(1)} km/h';
    } else {
      return '${speed.toStringAsFixed(1)} m/s';
    }
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
          content: Text('Destination set! Distance: ${_calculateDistanceToDestination(point)} away'),
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

    print('📍 Calculating route from $_currentPosition to $_destination');

    final route = await OSRMService.getRoute(_currentPosition!, _destination!);

    setState(() {
      if (route.isNotEmpty) {
        _fullRoute = route;
        _remainingRoute = List.from(route); // Initially, all route is remaining
        print('✅ Route calculated with ${route.length} points');
      } else {
        print('❌ Route calculation returned empty list');
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

  void _showStartTrackingDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Start Tracking?'),
          content: const Text(
              'Would you like to start tracking your activity from here?'
          ),
          actions: [
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _destination = null;
                  _fullRoute = [];
                  _remainingRoute = [];
                  _isNavigating = false;
                  _hasArrived = false;
                  _arrivalNotified = false;
                });
              },
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startTracking();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Start'),
            ),
          ],
        );
      },
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
    ActivityType currentType;
    switch (_selectedActivity) {
      case 'running':
        currentType = ActivityType.running;
        break;
      case 'walking':
        currentType = ActivityType.walking;
        break;
      case 'cycling':
        currentType = ActivityType.cycling;
        break;
      default:
        currentType = ActivityType.running;
    }

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
        backgroundColor: _activityColors[currentType]?.withValues(alpha: 0.9),
        foregroundColor: Colors.white,
        actions: [
          if (!_isTracking)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sports_score),
              onSelected: (value) {
                setState(() {
                  _selectedActivity = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'running',
                  child: Row(
                    children: [
                      Icon(Icons.directions_run, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Running'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'walking',
                  child: Row(
                    children: [
                      Icon(Icons.directions_walk, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Walking'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cycling',
                  child: Row(
                    children: [
                      Icon(Icons.directions_bike, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Cycling'),
                    ],
                  ),
                ),
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

              // Full route (faint blue) - shows the entire planned route
              if (_fullRoute.isNotEmpty && !_hasArrived)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _fullRoute,
                      color: Colors.blue.withValues(alpha: 0.2),
                      strokeWidth: 4,
                    ),
                  ],
                ),

              // Remaining route (bright blue) - DISAPPEARS AS YOU PASS
              if (_remainingRoute.isNotEmpty && !_hasArrived && _isTracking)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _remainingRoute,
                      color: Colors.blue.withValues(alpha: 0.8),
                      strokeWidth: 6,
                    ),
                  ],
                ),

              // Tracked route (activity color) - shows where you've been
              if (_trackedRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackedRoute,
                      color: _activityColors[currentType] ?? Colors.orange,
                      strokeWidth: 6,
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

              MarkerLayer(
                markers: [
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 40,
                      height: 40,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Transform.rotate(
                          angle: _heading * pi / 180,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _activityColors[currentType] ?? Colors.blue,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                _getDirectionalIcon(currentType),
                                color: _activityColors[currentType] ?? Colors.blue,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 40,
                      height: 40,
                      child: Stack(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                          if (_hasArrived)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
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
                          _activityColors[currentType] ?? Colors.blue,
                        ),
                        _buildStatItem(
                          'Duration',
                          _formatDuration(_currentDuration),
                          Icons.timer,
                          _activityColors[currentType] ?? Colors.blue,
                        ),
                        _buildStatItem(
                          'Speed',
                          _formatSpeed(_currentSpeed, _selectedActivity),
                          Icons.speed,
                          _activityColors[currentType] ?? Colors.blue,
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
                          _activityColors[currentType] ?? Colors.blue,
                        ),
                        _buildStatItem(
                          'Max Speed',
                          _formatSpeed(_maxSpeed, _selectedActivity),
                          Icons.flash_on,
                          _activityColors[currentType] ?? Colors.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Destination Info Card
          if (_isNavigating && !_isTracking && _destination != null)
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
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _hasArrived ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _hasArrived ? Icons.emoji_emotions : Icons.location_on,
                        color: _hasArrived ? Colors.green : Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasArrived ? 'You Have Arrived!' : 'Destination',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _hasArrived
                                ? 'Tap Start to begin your activity'
                                : '${_calculateDistanceToDestination(_destination!)} away',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_hasArrived && !_isTracking)
                      ElevatedButton(
                        onPressed: _startTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Start'),
                      ),
                  ],
                ),
              ),
            ),

          // Map Controls
          Positioned(
            top: _isTracking ? 200 : (_isNavigating ? 120 : 16),
            right: 16,
            child: Column(
              children: [
                Container(
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
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          _mapController.move(
                            _mapController.camera.center,
                            _mapController.camera.zoom + 1,
                          );
                        },
                      ),
                      Container(height: 1, width: 30, color: Colors.grey.shade300),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          _mapController.move(
                            _mapController.camera.center,
                            _mapController.camera.zoom - 1,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
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
                  child: IconButton(
                    icon: const Icon(Icons.my_location),
                    onPressed: _centerOnCurrentLocation,
                  ),
                ),
                const SizedBox(height: 8),
                if (!_isTracking && !_isNavigating)
                  Container(
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
                    child: IconButton(
                      icon: const Icon(Icons.place, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _isSelectingDestination = true;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tap on the map to set destination'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                  ),
                if (_isNavigating && !_isTracking)
                  Container(
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
                    child: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _destination = null;
                          _fullRoute = [];
                          _remainingRoute = [];
                          _isNavigating = false;
                          _hasArrived = false;
                          _arrivalNotified = false;
                        });
                      },
                    ),
                  ),
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
                      offset: const Offset(0, 2),
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
                        label: Text(
                          _isNavigating ? 'Start Navigation' : 'Start $_selectedActivity',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _activityColors[currentType],
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

  IconData _getDirectionalIcon(ActivityType type) {
    switch (type) {
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.cycling:
        return Icons.directions_bike;
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
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    _locationService.dispose();
    _markerAnimationController?.dispose();
    super.dispose();
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}