import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geolocator;

import '../services/location_service.dart';
import '../services/osrm_service.dart';
import '../services/activity_service.dart';
import '../models/activity.dart';
import '../widgets/activity_summary_card.dart';

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
  LatLng? _destination;

  // Route data
  List<LatLng> _fullRoute = [];
  List<LatLng> _remainingRoute = [];
  List<LatLng> _trackedRoute = [];

  // Track which points have been passed
  Set<int> _passedPointsIndices = {};

  // Navigation state
  bool _isTracking = false;
  bool _isSelectingDestination = false;
  bool _isNavigating = false;
  String _selectedActivity = 'running'; // Removed driving option
  bool _locationPermissionGranted = false;
  bool _isLoadingLocation = true;

  // ETA and route info
  double _totalDistance = 0;
  double _totalDuration = 0;
  String _formattedEta = "";
  String _formattedTotalDistance = "";

  // Arrival detection
  bool _hasArrived = false;
  double _arrivalThreshold = 20.0; // meters
  bool _arrivalNotified = false;

  // Live tracking metrics
  double _currentSpeed = 0;
  double _currentDistance = 0; // in km
  double _currentDuration = 0; // in seconds
  double _maxSpeed = 0;
  double _averageSpeed = 0;
  String _formattedPace = "--:--";

  Timer? _timer;
  Stopwatch _stopwatch = Stopwatch();
  LatLng? _lastPositionForDistance;
  DateTime? _lastTimeForSpeed;

  // For smooth location updates
  StreamSubscription<geolocator.Position>? _positionSubscription;

  // Animation for smooth marker movement
  AnimationController? _markerAnimationController;
  LatLng? _targetPosition;
  LatLng? _currentAnimatedPosition;
  double _heading = 0.0;

  static const int UPDATE_INTERVAL_MS = 100;
  static const int MARKER_ANIMATION_DURATION_MS = 300;

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
    _initializeLocation();
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

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _markerAnimationController?.dispose();
    _stopwatch.stop();
    _locationService.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);

    bool permissionGranted = await _locationService.checkAndRequestPermission();

    if (permissionGranted) {
      // Get initial position
      LatLng? location = await _locationService.getCurrentLocation();

      setState(() {
        _currentPosition = location ?? widget.currentLocation;
        _currentAnimatedPosition = _currentPosition;
        _previousPosition = _currentPosition;
        _locationPermissionGranted = true;
        _isLoadingLocation = false;
      });

      // Center map on location
      if (_currentPosition != null) {
        _mapController.move(_currentPosition!, 16);
      }

      // Start continuous location updates
      _startLocationUpdates();
    } else {
      setState(() {
        _locationPermissionGranted = false;
        _isLoadingLocation = false;
      });
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
              'Strava needs access to your location to track your runs, walks, and cycling activities. Please enable location permissions in settings.'
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                geolocator.Geolocator.openLocationSettings();
              },
            ),
          ],
        );
      },
    );
  }

  void _startLocationUpdates() {
    _positionSubscription = geolocator.Geolocator.getPositionStream(
      locationSettings: const geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // Update on EVERY movement
      ),
    ).listen((geolocator.Position position) {
      if (!mounted) return;

      final newPosition = LatLng(position.latitude, position.longitude);

      // Store previous position
      if (_currentPosition != null) {
        _previousPosition = _currentPosition;
      }

      // Animate marker to new position
      _animateMarkerToNewPosition(newPosition);

      setState(() {
        _currentPosition = newPosition;
        _currentSpeed = position.speed;

        // Update max speed
        if (_currentSpeed > _maxSpeed) {
          _maxSpeed = _currentSpeed;
        }

        // Check if arrived at destination
        if (_destination != null && !_hasArrived) {
          _checkArrival();
        }

        if (_isTracking) {
          // Add to tracked route
          _trackedRoute.add(newPosition);

          // Calculate distance
          if (_lastPositionForDistance != null) {
            double segmentDistance = geolocator.Geolocator.distanceBetween(
              _lastPositionForDistance!.latitude,
              _lastPositionForDistance!.longitude,
              newPosition.latitude,
              newPosition.longitude,
            );

            // Update distance (convert to km)
            _currentDistance += segmentDistance / 1000;

            // Calculate speed from time and distance
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

          _lastPositionForDistance = newPosition;
          _lastTimeForSpeed = DateTime.now();

          // Update remaining route
          if (_fullRoute.isNotEmpty) {
            _updateRemainingRoute(newPosition);
          }

          // Update activity service
          _activityService.addRoutePoint(
            newPosition,
            _currentSpeed,
            0,
          );
        }

        // Follow user when navigating
        if (_isNavigating && !_isTracking && !_hasArrived) {
          _mapController.move(newPosition, 16);
        }
      });
    });
  }

  void _updateRemainingRoute(LatLng currentPosition) {
    if (_fullRoute.isEmpty || _destination == null) return;

    // Find the closest point on the route
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

    // Mark points as passed if close to the route
    if (minDistance < 30) {
      setState(() {
        // Add points up to closestIndex to passed points
        for (int i = 0; i <= closestIndex; i++) {
          _passedPointsIndices.add(i);
        }

        // Rebuild remaining route
        _remainingRoute = [];
        for (int i = 0; i < _fullRoute.length; i++) {
          if (!_passedPointsIndices.contains(i)) {
            _remainingRoute.add(_fullRoute[i]);
          }
        }
      });
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

    if (distanceToDestination <= _arrivalThreshold && !_arrivalNotified) {
      _handleArrival();
    }
  }

  void _handleArrival() {
    setState(() {
      _hasArrived = true;
      _arrivalNotified = true;
      _remainingRoute = [];
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

    if (mounted) {
      _showActivitySummary();
    }

    // Reset after delay
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isTracking = false;
          _isNavigating = false;
          _destination = null;
          _fullRoute = [];
          _remainingRoute = [];
          _trackedRoute = [];
          _passedPointsIndices.clear();
          _hasArrived = false;
          _arrivalNotified = false;
          _currentDistance = 0;
          _currentDuration = 0;
          _maxSpeed = 0;
          _averageSpeed = 0;
          _formattedPace = "--:--";
          _lastPositionForDistance = null;
          _lastTimeForSpeed = null;
        });
      }
    });
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_emotions, color: Colors.green, size: 50),
              ),
              const SizedBox(height: 16),
              const Text('You Have Arrived! 🎉', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You have reached your destination.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              if (_isTracking) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('Distance: ${_formatDistance(_currentDistance * 1000)}'),
                      Text('Time: ${_formatDuration(_currentDuration)}'),
                    ],
                  ),
                ),
              ],
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
              _buildSummaryRow('Distance', _formatDistance(_currentDistance * 1000)),
              const Divider(),
              _buildSummaryRow('Duration', _formatDuration(_currentDuration)),
              const Divider(),
              _buildSummaryRow('Avg Speed', _formatSpeed(_averageSpeed)),
              const Divider(),
              _buildSummaryRow('Max Speed', _formatSpeed(_maxSpeed)),
              const Divider(),
              _buildSummaryRow('Avg Pace', _formattedPace),
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
      _passedPointsIndices.clear();
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

      if (_fullRoute.isNotEmpty) {
        _remainingRoute = List.from(_fullRoute);
      }
    });

    _stopwatch.reset();
    _stopwatch.start();

    // Update duration every 100ms for smooth display
    _timer = Timer.periodic(const Duration(milliseconds: UPDATE_INTERVAL_MS), (timer) {
      if (_isTracking && mounted) {
        setState(() {
          _currentDuration = _stopwatch.elapsedMilliseconds / 1000.0;

          if (_currentDuration > 0 && _currentDistance > 0) {
            _averageSpeed = (_currentDistance * 1000) / _currentDuration;

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
      _trackedRoute = [];
      _passedPointsIndices.clear();
      _hasArrived = false;
      _arrivalNotified = false;
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
      _passedPointsIndices.clear();
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

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_isSelectingDestination && !_isTracking) {
      setState(() {
        _destination = point;
        _isSelectingDestination = false;
        _isNavigating = true;
        _hasArrived = false;
        _arrivalNotified = false;
        _passedPointsIndices.clear();
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

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatDuration(double seconds) {
    int hrs = (seconds / 3600).floor();
    int mins = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hrs > 0) {
      return '${hrs}h ${mins}m';
    } else if (mins > 0) {
      return '${mins}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  String _formatSpeed(double speed) {
    return '${speed.toStringAsFixed(1)} m/s';
  }

  String _formatTime(DateTime time) {
    int hour = time.hour;
    int minute = time.minute;
    String period = hour >= 12 ? 'PM' : 'AM';

    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;

    return '$hour:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _calculateRoute() async {
    if (_currentPosition == null || _destination == null) return;

    final route = await OSRMService.getRoute(_currentPosition!, _destination!);

    // Get route details
    final details = await OSRMService.getRouteDetails(_currentPosition!, _destination!);

    setState(() {
      _fullRoute = route;
      _remainingRoute = List.from(route);
      _passedPointsIndices.clear();
      _totalDistance = details['distance'];
      _totalDuration = details['duration'];
      _formattedTotalDistance = _formatDistance(_totalDistance);

      DateTime eta = DateTime.now().add(Duration(seconds: _totalDuration.round()));
      _formattedEta = _formatTime(eta);
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

    Color currentColor = _activityColors[currentType] ?? Colors.blue;

    if (_isLoadingLocation) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Getting your location...'),
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
                const Icon(Icons.location_off, size: 80, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Location Permission Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Strava needs access to your location to track your activities.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => geolocator.Geolocator.openLocationSettings(),
                  child: const Text('Open Settings'),
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
          if (!_isTracking)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sports_score),
              onSelected: (value) => setState(() => _selectedActivity = value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'running', child: Row(children: [Icon(Icons.directions_run, color: Colors.orange), SizedBox(width: 8), Text('Running')])),
                const PopupMenuItem(value: 'walking', child: Row(children: [Icon(Icons.directions_walk, color: Colors.green), SizedBox(width: 8), Text('Walking')])),
                const PopupMenuItem(value: 'cycling', child: Row(children: [Icon(Icons.directions_bike, color: Colors.blue), SizedBox(width: 8), Text('Cycling')])),
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
              initialZoom: 16,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.strava',
              ),

              // Full route (faint gray)
              if (_fullRoute.isNotEmpty && !_hasArrived)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _fullRoute,
                      color: Colors.grey.withValues(alpha: 0.3),
                      strokeWidth: 4,
                    ),
                  ],
                ),

              // Remaining route (bright colored) - DISAPPEARS AS YOU PASS
              if (_remainingRoute.isNotEmpty && !_hasArrived && _isNavigating)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _remainingRoute,
                      color: currentColor.withValues(alpha: 0.8),
                      strokeWidth: 6,
                    ),
                  ],
                ),

              // Tracked route (your path)
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

              // Current position marker - ANIMATED
              MarkerLayer(
                markers: [
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer pulse
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: currentColor.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                            ),
                            // Inner dot
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
                                  ),
                                ],
                              ),
                            ),
                            // Direction indicator
                            if (_currentSpeed > 0.5)
                              Positioned(
                                top: 2,
                                child: Transform.rotate(
                                  angle: _heading * pi / 180,
                                  child: Container(
                                    width: 4,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // Destination marker
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 40,
                      height: 40,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (!_hasArrived)
                            const Icon(Icons.location_pin, color: Colors.red, size: 40),
                          if (_hasArrived)
                            const Icon(Icons.check_circle, color: Colors.green, size: 40),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Navigation Header
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
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formattedTotalDistance,
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
                              Icon(_activityIcons[currentType], size: 16, color: currentColor),
                              const SizedBox(width: 4),
                              Text(
                                _selectedActivity.capitalize(),
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
                  ],
                ),
              ),
            ),

          // Controls overlay
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
                    setState(() => _isSelectingDestination = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tap on the map to set destination'), duration: Duration(seconds: 3)),
                    );
                  }, color: Colors.red),
                ],
                if (_isNavigating && !_isTracking) ...[
                  const SizedBox(height: 8),
                  _buildControlButton(Icons.clear, () {
                    setState(() {
                      _destination = null;
                      _fullRoute = [];
                      _remainingRoute = [];
                      _isNavigating = false;
                      _hasArrived = false;
                      _arrivalNotified = false;
                      _passedPointsIndices.clear();
                    });
                  }, color: Colors.red),
                ],
              ],
            ),
          ),

          // Activity summary during tracking
          if (_isTracking)
            Positioned(
              top: 16,
              left: 16,
              right: 80,
              child: ActivitySummaryCard(
                distance: _currentDistance,
                duration: _currentDuration,
                speed: _currentSpeed,
                type: currentType,
              ),
            ),

          // Start/Stop buttons
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
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isTracking)
                      ElevatedButton.icon(
                        onPressed: _currentPosition != null ? _startTracking : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_isNavigating ? 'Start Navigation' : 'Start'),
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

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {Color color = Colors.blue}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
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