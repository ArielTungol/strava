import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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

    // Initialize after widget is built
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
    // Listen to location changes in real-time
    ref.listen(currentLocationProvider, (previous, next) {
      if (next != null && mounted) {
        debugPrint('📍 Moving to: ${next.latitude}, ${next.longitude}');
        _handleLocationUpdate(next);
      }
    });
  }

  void _handleLocationUpdate(LatLng newLocation) {
    // Update marker position with animation
    if (_currentAnimatedPosition == null) {
      setState(() {
        _currentAnimatedPosition = newLocation;
      });
    } else {
      _animateMarkerToNewPosition(newLocation);
    }

    // Add to path if tracking is active
    final isTracking = ref.read(currentActivityProvider) != null;
    if (isTracking) {
      setState(() {
        if (_traveledPath.isEmpty) {
          _traveledPath = [newLocation];
        } else {
          final lastPoint = _traveledPath.last;
          double distance = _calculateDistance(lastPoint, newLocation);
          if (distance > 2) { // Add point every 2 meters
            _traveledPath.add(newLocation);
            debugPrint('📍 Path point added: ${_traveledPath.length}');
          }
        }
      });
    }
  }

  Future<void> _initializeLocation() async {
    // Request permissions
    final permissionGranted = await ref.read(locationPermissionStateProvider.notifier).checkAndRequestPermission();
    if (!permissionGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required'),
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
      setState(() => _currentAnimatedPosition = newPosition);
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
      final double lat = startLat + (endLat - startLat) * t;
      final double lng = startLng + (endLng - startLng) * t;

      setState(() {
        _currentAnimatedPosition = LatLng(lat, lng);
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

  /// ✅ START BUTTON - Begins tracking
  void _startTracking() {
    final travelMode = ref.read(travelModeProvider);
    final activityType = _getActivityTypeFromString(travelMode);
    final currentLocation = ref.read(currentLocationProvider);

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get your location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Clear previous path and start fresh
    setState(() {
      _traveledPath = [currentLocation];
    });

    // Start activity
    ref.read(currentActivityProvider.notifier).startNewActivity(
      '${travelMode.capitalize()} ${DateTime.now().toString().substring(0, 16)}',
      activityType,
    );

    // Start location tracking
    ref.read(locationTrackingProvider.notifier).startTracking();

    // Update stats every second
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });

    // Center map
    _mapController.move(currentLocation, 16);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Started ${travelMode.capitalize()}!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  ActivityType _getActivityTypeFromString(String mode) {
    switch (mode) {
      case 'walking': return ActivityType.walking;
      case 'cycling': return ActivityType.cycling;
      default: return ActivityType.running;
    }
  }

  /// ✅ FINISH BUTTON - Saves to history
  Future<void> _stopTracking() async {
    debugPrint('🔴 Finishing activity...');

    // Stop timer
    _statsTimer?.cancel();

    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Save to Hive database
      await ref.read(currentActivityProvider.notifier).finishActivity();

      // Stop tracking
      ref.read(locationTrackingProvider.notifier).stopTracking();
      ref.read(currentSpeedProvider.notifier).resetSpeed();

      if (mounted) {
        Navigator.of(context).pop(); // Close loading

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Saved to history!'),
            backgroundColor: Colors.green,
          ),
        );

        _showActivitySummary();
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _cancelTracking() {
    _statsTimer?.cancel();
    ref.read(currentActivityProvider.notifier).cancelActivity();
    ref.read(locationTrackingProvider.notifier).stopTracking();
    ref.read(currentSpeedProvider.notifier).resetSpeed();

    setState(() => _traveledPath.clear());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cancelled'), backgroundColor: Colors.orange),
    );
  }

  void _showActivitySummary() {
    final activity = ref.read(currentActivityProvider);
    if (activity == null) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Activity Completed! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSummaryRow('Distance', _formatDistance(activity.distance)),
            _buildSummaryRow('Duration', _formatDuration(activity.duration)),
            _buildSummaryRow('Calories', '${activity.caloriesBurned} kcal'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _traveledPath.clear());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(2)}km';
  }

  String _formatDuration(double seconds) {
    int h = (seconds / 3600).floor();
    int m = ((seconds % 3600) / 60).floor();
    int s = (seconds % 60).floor();
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double R = 6371000;
    double lat1 = p1.latitude * pi / 180;
    double lat2 = p2.latitude * pi / 180;
    double deltaLat = (p2.latitude - p1.latitude) * pi / 180;
    double deltaLng = (p2.longitude - p1.longitude) * pi / 180;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

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
    final currentLocation = ref.watch(currentLocationProvider);
    final currentActivity = ref.watch(currentActivityProvider);
    final isTracking = currentActivity != null;
    final travelMode = ref.watch(travelModeProvider);
    final travelModeColor = _getTravelModeColor(travelMode);
    final currentSpeed = ref.watch(currentSpeedProvider);

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
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'running',
                  child: Row(children: [Icon(Icons.directions_run, color: Colors.orange), Text('Running')]),
                ),
                const PopupMenuItem(
                  value: 'walking',
                  child: Row(children: [Icon(Icons.directions_walk, color: Colors.green), Text('Walking')]),
                ),
                const PopupMenuItem(
                  value: 'cycling',
                  child: Row(children: [Icon(Icons.directions_bike, color: Colors.blue), Text('Cycling')]),
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
              initialZoom: 16,
            ),
            children: [
              // ✅ FIXED: Use CDN tile server with proper user agent
              TileLayer(
                urlTemplate: 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yourcompany.strava', // Replace with your app's bundle ID
                tileProvider: CancellableNetworkTileProvider(),
              ),

              // ✅ YOUR PATH - Draws as you move
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

              // ✅ YOUR MARKER - Moves with you
              if (_currentAnimatedPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 1000),
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: travelModeColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              color: travelModeColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ✅ OSM Attribution - Added as a separate positioned widget
          Positioned(
            bottom: 180,
            right: 8,
            child: GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://openstreetmap.org/copyright');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  '© OpenStreetMap',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ),
            ),
          ),

          // Live stats
          if (isTracking)
            Positioned(
              top: 16, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat('Distance', _formatDistance(currentActivity!.distance), Icons.straighten, travelModeColor),
                    _buildStat('Time', _formatDuration(currentActivity.duration), Icons.timer, travelModeColor),
                    _buildStat('Speed', '${currentSpeed.toStringAsFixed(1)} m/s', Icons.speed, travelModeColor),
                  ],
                ),
              ),
            ),

          // Map controls
          Positioned(
            bottom: 100, right: 16,
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

          // Start/Finish buttons
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
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
                        ),
                        child: const Text('Finish'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _cancelTracking,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Path info
          if (isTracking && _traveledPath.length > 1)
            Positioned(
              bottom: 140, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    Icon(Icons.route, color: travelModeColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatDistance(_calculateTotalDistance())} traveled',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, Color color) {
    return Column(children: [
      Icon(icon, color: color, size: 16),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
    ]);
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {Color color = Colors.blue}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Color _getTravelModeColor(String mode) {
    switch (mode) {
      case 'running': return Colors.orange;
      case 'walking': return Colors.green;
      case 'cycling': return Colors.blue;
      default: return Colors.orange;
    }
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