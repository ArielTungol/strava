import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';

import '../providers/activity_provider.dart';
import '../providers/location_provider.dart';
import '../providers/settings_provider.dart';
import '../models/activity.dart';

class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({super.key});

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Animation for smooth marker movement
  AnimationController? _markerAnimationController;
  LatLng? _currentAnimatedPosition;

  // Path tracking - stores your traveled route
  List<LatLng> _traveledPath = [];

  // Timer for updating stats
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _initializeMarkerAnimation();

    // Use WidgetsBinding to ensure the widget is built before initializing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocation();
      _setupLocationListener();
    });
  }

  void _initializeMarkerAnimation() {
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  void _setupLocationListener() {
    // Listen to location changes directly - Riverpod manages the subscription
    ref.listen(currentLocationProvider, (previous, next) {
      if (next != null && mounted) {
        debugPrint('📍 Location changed: ${next.latitude}, ${next.longitude}');
        _handleLocationUpdate(next);
      }
    });
  }

  void _handleLocationUpdate(LatLng newLocation) {
    // Update marker position
    if (_currentAnimatedPosition == null) {
      setState(() {
        _currentAnimatedPosition = newLocation;
      });
    } else {
      _animateMarkerToNewPosition(newLocation);
    }

    // Add to path if tracking
    final isTracking = ref.read(currentActivityProvider) != null;
    if (isTracking) {
      setState(() {
        if (_traveledPath.isEmpty) {
          _traveledPath = [newLocation];
        } else {
          final lastPoint = _traveledPath.last;
          double distance = _calculateDistance(lastPoint, newLocation);
          if (distance > 2) { // 2 meters threshold for smoother path
            _traveledPath.add(newLocation);
            debugPrint('📍 Path point added: ${_traveledPath.length}');
          }
        }
      });
    }
  }

  Future<void> _initializeLocation() async {
    // Check and request permissions
    final permissionGranted = await ref.read(locationPermissionStateProvider.notifier).checkAndRequestPermission();
    if (!permissionGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to track activities'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Get initial location
    final service = ref.read(locationServiceProvider);
    final location = await service.getCurrentLocation();

    if (location != null && mounted) {
      ref.read(currentLocationProvider.notifier).updateLocation(location);
      setState(() {
        _currentAnimatedPosition = location;
      });
      _mapController.move(location, 16);
    }
  }

  void _animateMarkerToNewPosition(LatLng newPosition) {
    if (_currentAnimatedPosition == null) {
      setState(() {
        _currentAnimatedPosition = newPosition;
      });
      return;
    }

    // Don't animate if same position
    if (_currentAnimatedPosition!.latitude == newPosition.latitude &&
        _currentAnimatedPosition!.longitude == newPosition.longitude) {
      return;
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

  void _centerOnCurrentLocation() {
    final currentLocation = ref.read(currentLocationProvider);
    if (currentLocation != null) {
      _mapController.move(currentLocation, 16);
    }
  }

  /// START BUTTON FUNCTION - Begins tracking
  void _startTracking() {
    final travelMode = ref.read(travelModeProvider);
    final activityType = _getActivityTypeFromString(travelMode);
    final currentLocation = ref.read(currentLocationProvider);

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get your location. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Clear previous path and start with current location
    setState(() {
      _traveledPath = [currentLocation];
    });

    // Start activity in service
    ref.read(currentActivityProvider.notifier).startNewActivity(
      '${travelMode.capitalize()} ${DateTime.now().toString().substring(0, 16)}',
      activityType,
    );

    // Start location tracking
    ref.read(locationTrackingProvider.notifier).startTracking();

    // Start timer to update UI every second
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {}); // Refresh UI to show updated stats
      }
    });

    // Center map on current location
    _mapController.move(currentLocation, 16);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Started ${travelMode.capitalize()}!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  ActivityType _getActivityTypeFromString(String mode) {
    switch (mode) {
      case 'walking':
        return ActivityType.walking;
      case 'cycling':
        return ActivityType.cycling;
      case 'running':
      default:
        return ActivityType.running;
    }
  }

  /// FINISH BUTTON FUNCTION - Saves to history
  Future<void> _stopTracking() async {
    debugPrint('🔴 Finish button pressed');

    // Stop timer
    _statsTimer?.cancel();

    // Check if mounted before showing dialog
    if (!mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Finish activity - this saves to Hive database
      await ref.read(currentActivityProvider.notifier).finishActivity();
      debugPrint('✅ Activity finished and saved to history');

      // Stop location tracking
      ref.read(locationTrackingProvider.notifier).stopTracking();
      ref.read(currentSpeedProvider.notifier).resetSpeed();

      // Close loading dialog and show success
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Activity saved to history!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Show activity summary
        _showActivitySummary();
      }
    } catch (e) {
      debugPrint('❌ Error finishing activity: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelTracking() {
    // Stop timer
    _statsTimer?.cancel();

    // Cancel activity
    ref.read(currentActivityProvider.notifier).cancelActivity();
    ref.read(locationTrackingProvider.notifier).stopTracking();
    ref.read(currentSpeedProvider.notifier).resetSpeed();

    // Clear path
    setState(() {
      _traveledPath.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Activity cancelled'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showActivitySummary() {
    final currentActivity = ref.read(currentActivityProvider);
    if (currentActivity == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Activity Completed! 🎉'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryRow('Distance', _formatDistance(currentActivity.distance)),
              const Divider(),
              _buildSummaryRow('Duration', _formatDuration(currentActivity.duration)),
              const Divider(),
              _buildSummaryRow('Avg Speed', _formatSpeed(currentActivity.averageSpeed, currentActivity.type)),
              const Divider(),
              _buildSummaryRow('Calories', '${currentActivity.caloriesBurned} kcal'),
              if (_traveledPath.isNotEmpty) ...[
                const Divider(),
                _buildSummaryRow('Route Points', '${_traveledPath.length}'),
                _buildSummaryRow('Total Distance', _formatDistance(_calculateTotalDistance())),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Clear path after viewing summary
                setState(() {
                  _traveledPath.clear();
                });
              },
              child: const Text('OK'),
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
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(2)}km';
  }

  String _formatDuration(double seconds) {
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  String _formatSpeed(double speed, ActivityType type) {
    if (type == ActivityType.cycling) {
      return '${(speed * 3.6).toStringAsFixed(1)} km/h';
    }
    return '${speed.toStringAsFixed(1)} m/s';
  }

  // Calculate distance between two points (Haversine formula)
  double _calculateDistance(LatLng p1, LatLng p2) {
    const double R = 6371000; // Earth's radius in meters
    double lat1 = p1.latitude * pi / 180;
    double lat2 = p2.latitude * pi / 180;
    double deltaLat = (p2.latitude - p1.latitude) * pi / 180;
    double deltaLng = (p2.longitude - p1.longitude) * pi / 180;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  // Calculate total distance traveled
  double _calculateTotalDistance() {
    if (_traveledPath.length < 2) return 0;

    double total = 0;
    for (int i = 0; i < _traveledPath.length - 1; i++) {
      total += _calculateDistance(_traveledPath[i], _traveledPath[i + 1]);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers for real-time updates
    final currentLocation = ref.watch(currentLocationProvider);
    final currentActivity = ref.watch(currentActivityProvider);
    final isTracking = currentActivity != null;
    final travelMode = ref.watch(travelModeProvider);
    final travelModeColor = _getTravelModeColor(travelMode);
    final currentSpeed = ref.watch(currentSpeedProvider);

    // Force update when location changes
    if (currentLocation != null && mounted) {
      // This ensures the marker updates immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentAnimatedPosition == null) {
          setState(() {
            _currentAnimatedPosition = currentLocation;
          });
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Activity'),
        backgroundColor: travelModeColor.withValues(alpha: 0.9),
        foregroundColor: Colors.white,
        actions: [
          if (!isTracking)
            PopupMenuButton<String>(
              icon: const Icon(Icons.directions),
              onSelected: (value) => ref.read(travelModeProvider.notifier).setMode(value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'running',
                  child: Row(
                    children: [
                      Icon(Icons.directions_run, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Running')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'walking',
                  child: Row(
                    children: [
                      Icon(Icons.directions_walk, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Walking')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cycling',
                  child: Row(
                    children: [
                      Icon(Icons.directions_bike, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Cycling')
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
              initialCenter: currentLocation ?? const LatLng(14.5995, 120.9842),
              initialZoom: 15,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.strava',
                tileProvider: CancellableNetworkTileProvider(),
              ),

              // ✅ YOUR PATH POLYLINE - Shows where you've been
              if (_traveledPath.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _traveledPath,
                      color: travelModeColor.withValues(alpha: 0.8),
                      strokeWidth: 4,
                    ),
                  ],
                ),

              // Markers
              MarkerLayer(
                markers: [
                  // ✅ CURRENT POSITION MARKER - Moves with you!
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeInOut,
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: travelModeColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Inner dot
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: travelModeColor,
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
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // LIVE TRACKING STATS
          if (isTracking && currentActivity != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCompactStat(
                      value: _formatDistance(currentActivity.distance),
                      icon: Icons.straighten,
                      color: travelModeColor,
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    _buildCompactStat(
                      value: _formatDuration(currentActivity.duration),
                      icon: Icons.timer,
                      color: travelModeColor,
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    _buildCompactStat(
                      value: _formatSpeed(currentSpeed, currentActivity.type),
                      icon: Icons.speed,
                      color: travelModeColor,
                    ),
                  ],
                ),
              ),
            ),

          // Map controls
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
              ],
            ),
          ),

          // START/FINISH BUTTONS
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
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isTracking)
                      ElevatedButton(
                        onPressed: currentLocation != null ? _startTracking : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: travelModeColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(100, 36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Start'),
                      ),
                    if (isTracking) ...[
                      ElevatedButton(
                        onPressed: _stopTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(80, 36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // PATH INFO - Shows distance traveled
          if (isTracking && _traveledPath.length > 1)
            Positioned(
              bottom: 140,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.route, color: travelModeColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatDistance(_calculateTotalDistance())} traveled',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getTravelModeColor(String mode) {
    switch (mode) {
      case 'running':
        return Colors.orange;
      case 'walking':
        return Colors.green;
      case 'cycling':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  Widget _buildCompactStat({required String value, required IconData icon, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
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

  @override
  void dispose() {
    _statsTimer?.cancel();
    _markerAnimationController?.dispose();
    super.dispose();
  }
}

extension StringExtension on String {
  String capitalize() => "${this[0].toUpperCase()}${substring(1)}";
}