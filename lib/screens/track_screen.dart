import 'dart:async';
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

  LatLng? _currentPosition;
  LatLng? _destination;
  List<LatLng> _fullRoute = []; // Complete route from start to destination
  List<LatLng> _remainingRoute = []; // Route that hasn't been traveled yet (disappears as you pass)
  List<LatLng> _trackedRoute = [];

  bool _isTracking = false;
  bool _isSelectingDestination = false;
  bool _isNavigating = false;
  String _selectedActivity = 'running';
  bool _locationPermissionGranted = false;
  bool _isLoadingLocation = true;

  // Arrival detection
  bool _hasArrived = false;
  double _arrivalThreshold = 20.0;
  bool _arrivalNotified = false;

  double _currentSpeed = 0;
  double _currentDistance = 0;
  double _currentDuration = 0;
  Timer? _timer;

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
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    // First, check and request permissions
    bool permissionGranted = await _locationService.checkAndRequestPermission();

    if (permissionGranted) {
      // Try to get current location
      LatLng? location = await _locationService.getCurrentLocation();

      setState(() {
        _currentPosition = location ?? widget.currentLocation;
        _locationPermissionGranted = true;
        _isLoadingLocation = false;
      });

      // Center map on location if we have it
      if (_currentPosition != null) {
        _mapController.move(_currentPosition!, 15);
      }

      // Start location updates
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
    _locationService.startTracking(
      onPositionChanged: (position) {
        setState(() {
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

            _currentDistance = _activityService.currentDistance;
            _currentDuration = _activityService.currentActivity?.duration ?? 0;

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
      },
      onSpeedChanged: (speed) {
        setState(() {
          _currentSpeed = speed;
        });
      },
    );
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
    // This makes the polyline disappear as you pass
    if (minDistance < 50) { // Within 50 meters of the route
      // Add a small offset to ensure smooth disappearance
      int newStartIndex = closestIndex + 2;
      if (newStartIndex < _fullRoute.length) {
        _remainingRoute = _fullRoute.sublist(newStartIndex);
      } else {
        _remainingRoute = [];
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

    _showArrivalDialog();

    if (_isTracking) {
      _autoStopTracking();
    }
  }

  void _autoStopTracking() async {
    await _activityService.finishActivity();
    _timer?.cancel();

    _showArrivalDialog();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activity completed! Distance: ${_activityService.currentActivity?.formattedDistance ?? '0'}'),
          backgroundColor: Colors.green,
        ),
      );
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
      _hasArrived = false;
      _arrivalNotified = false;

      // Initialize remaining route as full route when starting
      if (_fullRoute.isNotEmpty) {
        _remainingRoute = List.from(_fullRoute);
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentDuration = _activityService.currentActivity?.duration ?? 0;
      });
    });
  }

  void _stopTracking() async {
    await _activityService.finishActivity();
    _timer?.cancel();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _destination = null;
      _fullRoute = [];
      _remainingRoute = [];
      _hasArrived = false;
      _arrivalNotified = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activity saved! Distance: ${_activityService.currentActivity?.formattedDistance ?? '0'}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _cancelTracking() {
    _activityService.cancelActivity();
    _timer?.cancel();

    setState(() {
      _isTracking = false;
      _isNavigating = false;
      _destination = null;
      _fullRoute = [];
      _remainingRoute = [];
      _trackedRoute = [];
      _currentDistance = 0;
      _currentDuration = 0;
      _hasArrived = false;
      _arrivalNotified = false;
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

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  Future<void> _calculateRoute() async {
    if (_currentPosition == null || _destination == null) return;

    final route = await OSRMService.getRoute(_currentPosition!, _destination!);
    setState(() {
      _fullRoute = route;
      _remainingRoute = List.from(route); // Initially, all route is remaining
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
                  'Strava needs access to your location to track your activities. Please enable location permissions in settings.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    geolocator.Geolocator.openLocationSettings();
                  },
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
              ),

              // Full route (faint blue) - shows where you need to go
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

              // Tracked route
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

              // Current position marker
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _activityColors[currentType] ?? Colors.orange,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 5,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.navigation,
                            color: _activityColors[currentType] ?? Colors.orange,
                            size: 16,
                          ),
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

          // Controls overlay
          Positioned(
            top: 16,
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

  @override
  void dispose() {
    _timer?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}