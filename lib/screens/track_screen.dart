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

  // Path tracking
  List<LatLng> _pathPoints = [];

  @override
  void initState() {
    super.initState();
    _initializeMarkerAnimation();
    _initializeLocation();
  }

  void _initializeMarkerAnimation() {
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  Future<void> _initializeLocation() async {
    // Request permission and get initial location
    await ref.read(locationPermissionStateProvider.notifier).checkAndRequestPermission();

    final locationNotifier = ref.read(currentLocationProvider.notifier);
    final service = ref.read(locationServiceProvider);

    final location = await service.getCurrentLocation();
    if (location != null) {
      locationNotifier.updateLocation(location);
      setState(() {
        _currentAnimatedPosition = location;
      });
      _mapController.move(location, 15);
    }
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

    final targetPosition = newPosition;
    _markerAnimationController?.stop();
    _markerAnimationController?.reset();

    final startLat = _currentAnimatedPosition!.latitude;
    final startLng = _currentAnimatedPosition!.longitude;
    final endLat = targetPosition.latitude;
    final endLng = targetPosition.longitude;

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

  void _startTracking() {
    final travelMode = ref.read(travelModeProvider);
    final activityType = _getActivityTypeFromString(travelMode);

    // Clear previous path points
    setState(() {
      _pathPoints.clear();
    });

    ref.read(currentActivityProvider.notifier).startNewActivity(
      '${travelMode.capitalize()} ${DateTime.now().toString().substring(0, 16)}',
      activityType,
    );

    ref.read(locationTrackingProvider.notifier).startTracking();
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

  Future<void> _stopTracking() async {
    await ref.read(currentActivityProvider.notifier).finishActivity();
    ref.read(locationTrackingProvider.notifier).stopTracking();
    ref.read(currentSpeedProvider.notifier).resetSpeed();

    if (mounted) {
      _showActivitySummary();
    }
  }

  void _cancelTracking() {
    ref.read(currentActivityProvider.notifier).cancelActivity();
    ref.read(locationTrackingProvider.notifier).stopTracking();
    ref.read(currentSpeedProvider.notifier).resetSpeed();

    // Clear path points when canceling
    setState(() {
      _pathPoints.clear();
    });
  }

  void _showActivitySummary() {
    final currentActivity = ref.read(currentActivityProvider);
    if (currentActivity == null) return;

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
              _buildSummaryRow('Max Speed', _formatSpeed(currentActivity.maxSpeed ?? 0, currentActivity.type)),
              const Divider(),
              _buildSummaryRow('Calories', '${currentActivity.caloriesBurned} kcal'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
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
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatDuration(double seconds) {
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hours > 0) return '${hours}h ${minutes}min';
    if (minutes > 0) return '${minutes}min';
    return '${secs}sec';
  }

  String _formatSpeed(double speed, ActivityType type) {
    if (type == ActivityType.cycling) {
      return '${(speed * 3.6).toStringAsFixed(1)} km/h';
    }
    return '${speed.toStringAsFixed(1)} m/s';
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers
    final currentLocation = ref.watch(currentLocationProvider);
    final currentActivity = ref.watch(currentActivityProvider);
    final isTracking = currentActivity != null;
    final travelMode = ref.watch(travelModeProvider);
    final travelModeColor = _getTravelModeColor(travelMode);
    final currentSpeed = ref.watch(currentSpeedProvider);
    final locationHistory = ref.watch(locationHistoryProvider);

    // Update path points from location history when tracking
    if (isTracking && locationHistory.isNotEmpty) {
      setState(() {
        _pathPoints = locationHistory;
      });
    }

    // Update animated position when current location changes
    if (currentLocation != null && _currentAnimatedPosition != currentLocation) {
      _animateMarkerToNewPosition(currentLocation);
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

              // Path polyline - shows the completed route
              if (_pathPoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _pathPoints,
                      color: travelModeColor.withValues(alpha: 0.8),
                      strokeWidth: 4,
                    ),
                  ],
                ),

              // Markers
              MarkerLayer(
                markers: [
                  // Current position marker
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
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

          // Live tracking stats
          if (isTracking)
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
                      value: _formatDistance(currentActivity?.distance ?? 0),
                      icon: Icons.straighten,
                      color: travelModeColor,
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    _buildCompactStat(
                      value: _formatDuration(currentActivity?.duration ?? 0),
                      icon: Icons.timer,
                      color: travelModeColor,
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    _buildCompactStat(
                      value: _formatSpeed(currentSpeed, currentActivity?.type ?? ActivityType.running),
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

          // Start/Stop buttons
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

          // Path stats when tracking
          if (isTracking && _pathPoints.length > 1)
            Positioned(
              bottom: 100,
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
                      '${_pathPoints.length} points',
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
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
    _markerAnimationController?.dispose();
    super.dispose();
  }
}

extension StringExtension on String {
  String capitalize() => "${this[0].toUpperCase()}${substring(1)}";
}